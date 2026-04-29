# Tuning the profiler

`@perfetto` calibrates the sampling rate automatically, so for most code
you don't need to tune anything. This page covers the knobs you *can*
reach for when the defaults aren't quite right, and how to bypass the
calibration loop entirely when your workload has side effects.

## How the auto-calibration works

`@perfetto` runs your expression a few times. The first round uses a coarse
10 ms sampling delay just to time the workload. Each subsequent round
sharpens the delay so that the profile buffer fills to roughly half, while
keeping profiler overhead bounded. Only the **final** run is shown.

That means:

- Short workloads automatically get a sub-millisecond sampling rate.
- Long workloads automatically get a coarser rate, so your browser doesn't
  choke rendering millions of slices.
- You don't have to call `Profile.init` yourself.

## Calibration knobs

You can pass trailing `key = value` arguments to `@perfetto` (or
`@perfetto_open`) to nudge the calibration:

```julia
using ProfilePerfetto

# Cap calibration at 4 rounds and don't sharpen below 10 μs:
@perfetto my_workload() max_rounds=4 min_delay=1e-5

# Bigger sample buffer if your traces are getting truncated:
@perfetto my_workload() buffer_slots=50_000_000
```

The full list:

- `initial_delay::Float64` (default `0.01`, i.e. 10 ms) — sampling delay
  used for the first calibration round.
- `min_delay::Float64` (default `1e-7`, i.e. 0.1 μs) — hard floor on the
  sampling delay. Raise it if you're seeing huge profile overhead on very
  fast workloads.
- `buffer_slots::Int` (default `10_000_000`, ~80 MB) — size of the profile
  sample buffer. The loop targets ~50 % fill; bump this if your traces are
  getting truncated.
- `max_rounds::Int` (default `6`) — maximum number of times the expression
  is run during calibration.
- `max_inflation::Float64` (default `10.0`) — largest allowed ratio of
  measured wall time to the overhead-free baseline. Calibration backs off
  the sampling delay so profiler overhead can't blow runtime up by more
  than this factor.
- `max_step::Float64` (default `8.0`) — maximum factor by which the delay
  is allowed to shrink between consecutive rounds.

## Side effects: skip the macro

The calibration loop runs your expression multiple times. If that's not
acceptable — your code mutates shared state, writes to a file, hits a
network — drive `Profile` yourself and pass the data to
[`perfetto_view`](@ref) or [`perfetto_open`](@ref):

```julia
using Profile, ProfilePerfetto

Profile.init(n = 10^7, delay = 0.0001)   # 100 μs → 10 kHz
Profile.clear()
Profile.@profile my_workload()           # runs exactly once

perfetto_view()                          # in a notebook
# or
perfetto_open()                          # opens in your browser
```

`Profile.init`'s parameters are documented in the
[`Profile` stdlib docs](https://docs.julialang.org/en/v1/stdlib/Profile/):

- `delay` — seconds between samples. Default is `0.001` (1 ms). Smaller =
  finer-grained chart, more overhead, fills the buffer faster.
- `n` — maximum number of instruction-pointer slots in the sample buffer.

## Including C frames

By default Julia hides internal C frames (libuv, GC internals, etc.). If
you're debugging an FFI call or want to see where garbage collection is
eating your time, fetch profile data manually:

```julia
using Profile, ProfilePerfetto

Profile.clear()
Profile.@profile my_workload()

data   = Profile.fetch(; include_meta = true)
lidict = Profile.getdict(data)           # default hides C frames; pass C = true to include

perfetto_view(data, lidict)
```

## More from the `Profile` stdlib

Everything in the [`Profile` stdlib docs](https://docs.julialang.org/en/v1/stdlib/Profile/)
composes with ProfilePerfetto. A few highlights worth knowing:

- `Profile.print()` — text dump of the same samples ProfilePerfetto visualizes.
- `Profile.Allocs` — allocation profiler (tracks *where* you allocate, not
  where you spend CPU time). ProfilePerfetto only handles the CPU profiler.
- `Profile.fetch(; include_meta = true)` — raw sample data, ready to pass
  into [`perfetto_view`](@ref) or [`perfetto_open`](@ref).
