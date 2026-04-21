# Tuning the profiler

`ProfilePerfetto` is just a visualizer — the sampling itself is done by
Julia's stdlib [`Profile`](https://docs.julialang.org/en/v1/stdlib/Profile/).
That means every knob `Profile` exposes works here too. The two you're most
likely to reach for are the **sampling rate** and the **buffer size**.

## Sampling rate & buffer size: `Profile.init`

```julia
using Profile

Profile.init(n = 10^7, delay = 0.0001)
```

- `delay` — seconds between samples. Default is `0.001` (1 ms, i.e. 1000 Hz).
  Smaller = finer-grained chart, more overhead, fills the buffer faster.
- `n` — maximum number of instruction-pointer slots in the sample buffer.
  Default is around 10⁶. If the buffer fills up, sampling silently stops —
  Julia will warn you when you fetch the data.

Call `Profile.init()` with no arguments to check the current settings.

### When to lower `delay` (faster sampling)

For very short workloads, or when a critical function only runs briefly,
1 ms is too coarse. Try:

```julia
using Profile, ProfilePerfetto

Profile.init(n = 10^7, delay = 0.0001)   # 100 μs → 10 kHz

@profileperfetto short_but_important()
```

You'll probably also need to bump `n`, because 10× the sample rate produces
10× the data.

### When to raise `delay` (slower sampling)

For long-running code (tens of seconds or minutes), 1 ms sampling produces
so much data that your browser chokes rendering the chart. Try:

```julia
Profile.init(n = 10^7, delay = 0.01)     # 10 ms → 100 Hz

@profileperfetto long_batch_job()
```

You lose fine detail, but the big hotspots still dominate — statistically,
that's all you need.

## Including C frames

By default Julia hides internal C frames (libuv, GC internals, etc.). If
you're debugging an FFI call or want to see where garbage collection is
eating your time, fetch profile data manually and pass it through:

```julia
using Profile, ProfilePerfetto

Profile.clear()
Profile.@profile my_workload()

# Nothing in ProfilePerfetto exposes `C = true` directly — but you can
# call the underlying machinery yourself if you really need C frames.
data   = Profile.fetch(; include_meta = true)
lidict = Profile.getdict(data)

profileperfetto_view(data, lidict)
```

## Profiling a specific task

Starting in Julia 1.11, `Profile` can target a single `Task`:

```julia
using Profile, ProfilePerfetto

t = @task heavy_work()
schedule(t)

Profile.clear()
Profile.take_heap_snapshot  # for memory — profiling is similar
# Full per-task profiling requires the `Profile.@profile` machinery set up
# around the task; see the stdlib docs for the exact current API in your
# Julia version.

profileperfetto_view()
```

## Clearing the buffer

Profile data is cumulative — if you `Profile.@profile` twice without clearing,
the samples pile up. `@profileperfetto` calls [`Profile.clear`](https://docs.julialang.org/en/v1/stdlib/Profile/#Profile.clear)
for you, but if you're using `Profile.@profile` directly, do it yourself:

```julia
using Profile

Profile.clear()
Profile.@profile my_workload()
```

## More from the `Profile` stdlib

Everything in the [`Profile` stdlib docs](https://docs.julialang.org/en/v1/stdlib/Profile/)
composes with ProfilePerfetto. A few highlights worth knowing:

- `Profile.print()` — text dump of the same samples ProfilePerfetto visualizes.
- `Profile.Allocs` — allocation profiler (tracks *where* you allocate, not
  where you spend CPU time). ProfilePerfetto only handles the CPU profiler.
- `Profile.fetch(; include_meta = true)` — raw sample data, ready to pass
  into [`profileperfetto_view`](@ref) or [`profileperfetto_open`](@ref).

## Cheat sheet

```julia
using Profile, ProfilePerfetto

# 1. Configure (optional, but powerful)
Profile.init(n = 10^7, delay = 0.0001)

# 2. Warm up (skip compilation)
my_workload()

# 3. Profile + visualize in a notebook
@profileperfetto my_workload()

# 3'. Profile + visualize from the REPL
Profile.clear()
Profile.@profile my_workload()
profileperfetto_open()
```
