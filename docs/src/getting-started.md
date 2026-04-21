# Getting started

Let's pretend you've written a function that feels slow. We'll profile it,
read the flame chart, and find the bottleneck. No prior profiling experience
required.

## Step 1 — Something to profile

Paste this into a Julia session (ideally a Pluto, VS Code, or Jupyter notebook):

```julia
using ProfilePerfetto

function count_primes(n)
    count = 0
    for i in 2:n
        if is_prime(i)
            count += 1
        end
    end
    return count
end

function is_prime(n)
    n < 2 && return false
    for d in 2:(n-1)         # a deliberately naive loop
        n % d == 0 && return false
    end
    return true
end
```

## Step 2 — Profile it

```julia
@perfetto count_primes(50_000)
```

This macro does three things:

1. Clears any old profile data (`Profile.clear()`).
2. Runs your expression under `Profile.@profile`, which samples the call
   stack many times per second.
3. Hands the samples to Perfetto and renders an interactive chart.

## Step 3 — Reading the flame chart

You'll see a horizontal timeline. Time flows left-to-right; each row is a
stack frame. The function at the **top** of a stack was the one actually
running when the sampler fired — that's where the time is going.

Things you can do:

| Action            | How                                        |
| ----------------- | ------------------------------------------ |
| Pan               | Click and drag, or use `A` / `D`           |
| Zoom              | Scroll, or use `W` / `S`                   |
| See details       | Click a bar — file and line appear at the bottom |
| Select a range    | Shift-drag — total time & counts in sidebar |

In our prime-counting example, you'll see `is_prime` dominating the chart,
with most of the time spent inside its inner `for` loop. That's the smoking
gun: replace `2:(n-1)` with `2:isqrt(n)` and re-run.

## Step 4 — Re-run and confirm

After your fix:

```julia
@perfetto count_primes(50_000)
```

The `is_prime` bar should shrink dramatically. Profiling isn't just for
*finding* problems — it's also how you *confirm* you fixed them. 🎯

## Profiling without the macro

Sometimes you already have profile data — maybe collected with `Profile.@profile`
directly, or from a long-running session. Two options:

```julia
# View what's already in the Profile buffer (in an IDE)
perfetto_view()

# Create HTML file and open in your browser (works anywhere, including the plain REPL)
perfetto_open()
```

Both accept the same `data, lidict` pair that `Profile.fetch` returns, so you
can also do:

```julia
using Profile

Profile.clear()
Profile.@profile my_workload()

data   = Profile.fetch(; include_meta = true)
lidict = Profile.getdict(data)

perfetto_view(data, lidict; name = "Today's run")
```

## Common gotchas

!!! warning "The first run includes compilation time"
    Julia compiles each method the first time it runs. That compilation shows
    up in your flame chart as `jl_type_infer`, `Core.Compiler.*`, or similar.
    **Always run your workload once before profiling**, so you're measuring
    the steady-state, not the compile.

!!! warning "Too-fast workloads produce empty charts"
    The default sampler fires roughly every 1 ms. If your code finishes in
    under a millisecond you'll collect zero samples. Either wrap it in a loop
    or lower the sampling delay — see [Tuning the profiler](@ref).

!!! tip "Threaded code shows up on separate rows"
    Each OS thread gets its own track in the chart. Great for spotting one
    thread that's twiddling its thumbs while another carries the load.
