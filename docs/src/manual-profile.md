# Using `Profile.@profile` manually

The [`@perfetto`](@ref) macro is the easy path: it runs your code, picks a
good sampling rate, and renders the chart in one step. But sometimes you
need more control:

- Your workload has **side effects** and shouldn't be executed multiple
  times by the auto-calibration loop.
- You want to profile a **long-running session** and visualize whatever
  samples have accumulated so far.
- You're collecting samples in one process (e.g. a server) and want to
  view them somewhere else.
- You want to use [`Profile`](https://docs.julialang.org/en/v1/stdlib/Profile/)'s
  own knobs — `Profile.init`, `Profile.@profile`, `@profile sample_rate=…`,
  etc. — directly.

In all of these cases, collect samples with the `Profile` stdlib yourself,
then hand them to `perfetto_view` (for in-notebook display) or
`perfetto_open` (for the browser).

## The basic recipe

```julia
using Profile, ProfilePerfetto

Profile.clear()
Profile.@profile my_workload()        # runs exactly once

perfetto_view()
```

That's it. With no arguments, `perfetto_view` (and `perfetto_open`) read
whatever samples are currently sitting in Julia's profile buffer — the
same buffer that `Profile.@profile` just wrote to.

```julia
# In a notebook (Pluto / VS Code / Jupyter):
perfetto_view()

# In the plain REPL, or whenever you want a full browser tab:
perfetto_open()
```

## Tuning the sample rate

Auto-calibration is what `@perfetto` does for you. When you drive
`Profile` yourself, you pick the rate. The default is one sample every
1 ms, which is often too coarse for fast workloads and too fine for
long ones.

```julia
using Profile, ProfilePerfetto

# Sample every 100 µs — good for workloads in the millisecond range.
Profile.init(; delay = 0.0001)

Profile.clear()
Profile.@profile my_workload()

perfetto_view(; name = "my_workload, 100µs sampling")
```

Rule of thumb: aim for a few hundred to a few thousand samples per run.
Fewer than ~50 and the chart is too sparse to read; more than ~100,000
and the buffer fills up and Perfetto starts to chug.

See [Tuning the profiler](@ref) for more on choosing a rate.

## Passing data explicitly

If you've already pulled samples out of the profile buffer — for example
to save them to disk, or to ship them between processes — pass them in
directly:

```julia
data   = Profile.fetch(; include_meta = true)
lidict = Profile.getdict(data)

perfetto_view(data, lidict; name = "Today's run")
```

!!! warning "Always use `include_meta = true`"
    `ProfilePerfetto` needs the per-sample metadata (thread id, task id,
    timestamps) that Julia's `Profile.fetch` only emits when
    `include_meta = true`. Without it, the parser can't reconstruct the
    timeline.

## Profiling a long-running session

You don't have to stop sampling before viewing. Call `perfetto_view()`
whenever you want a snapshot — the profile buffer keeps accumulating
in the background.

```julia
Profile.init(; delay = 0.001, n = 10_000_000)   # bigger buffer
Profile.clear()
Profile.@profile run_server()        # runs for a while…

# Later, in another cell or after Ctrl-C:
perfetto_view()
```

## See also

- [`perfetto_view`](@ref) — render in a notebook.
- [`perfetto_open`](@ref) — open in the browser.
- [Tuning the profiler](@ref) — picking a sample rate.
- The [Julia `Profile` stdlib docs](https://docs.julialang.org/en/v1/stdlib/Profile/).
