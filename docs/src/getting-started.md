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

That's it. Behind the scenes, `@perfetto`:

1. Runs your expression once at a coarse sampling rate to see how long it takes.
2. Runs it again with a sharper sampling rate so the flame chart has plenty
   of detail without being dominated by profiler overhead.
3. Hands the resulting samples to Perfetto and renders an interactive chart
   inline in your notebook.

!!! warning "Your code runs multiple times"
    Because of the calibration loop, `@perfetto` evaluates the expression
    several times. Don't use it on code with side effects — see
    [Profiling pre-collected data](@ref) below.

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

## Which macro to use?

- **`@perfetto expr`** / **`@perfetto_view expr`** — profiles `expr` and
  renders the chart inline in a Pluto, VS Code, or Jupyter notebook.
  `@perfetto` is an exported alias for `@perfetto_view`.
- **`@perfetto_open expr`** — profiles `expr` and opens the chart in your
  default web browser. Use this in the plain REPL.

Both macros accept the same trailing `key = value` calibration options —
see [Tuning the profiler](@ref).

## Profiling pre-collected data

If your workload has side effects, or you already have profile data —
maybe collected with `Profile.@profile` directly, or from a long-running
session — skip the macro and drive `Profile` yourself:

```julia
using Profile, ProfilePerfetto

Profile.clear()
Profile.@profile my_workload()        # runs exactly once

perfetto_view()                       # or perfetto_open() in the REPL
```

See [Using `Profile.@profile` manually](@ref) for the full walkthrough.

## Common gotchas

!!! warning "The first run includes compilation time"
    Julia compiles each method the first time it runs. That compilation shows
    up in your flame chart as `jl_type_infer`, `Core.Compiler.*`, or similar.
    `@perfetto`'s calibration loop runs your code several times, so by the
    final, displayed run things are usually warm — but if you want to be
    sure, run your workload once before profiling.

!!! tip "Threaded code shows up on separate rows"
    Each OS thread gets its own track in the chart. Great for spotting one
    thread that's twiddling its thumbs while another carries the load.
