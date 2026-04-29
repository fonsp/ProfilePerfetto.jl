### ---- The macros


function _parse_kw_args(args, macroname)
    kws = Expr[]
    for a in args
        if isa(a, Expr) && a.head === :(=) && isa(a.args[1], Symbol)
            push!(kws, Expr(:kw, a.args[1], esc(a.args[2])))
        else
            error("$(macroname): expected `key = value` argument, got $(a)")
        end
    end
    return kws
end

function _perfetto_macro(f, expr, kw_args, macroname)
    kws = _parse_kw_args(kw_args, macroname)
    quote
        local _data, _lidict, _wall_ns =
            $(_autocalibrate)(() -> $(esc(expr)); $(kws...))
        $(f)(_data, _lidict; filter_sentinel = true, wall_time_ns = _wall_ns)
    end
end

"""
    @perfetto expr [key=value ...]

Profile `expr` and render the result as an interactive
[Perfetto](https://ui.perfetto.dev) flame chart, inline in a Pluto, VS Code,
or Jupyter notebook.

The sampling rate is **calibrated automatically**: `expr` is run a few times,
starting at a coarse 10 ms sampling delay, and the delay is sharpened on
each round so the final, displayed run captures plenty of detail without
spending all its time inside the sampler. You don't have to pick a `delay`
by hand.

!!! warning "Your code runs multiple times"
    Because of the calibration loop, `expr` is evaluated several times (up
    to `max_rounds`, default 6). Don't use `@perfetto` on code with
    observable side effects (mutating shared state, writing files, sending
    network requests, …) — wrap the workload in something idempotent first,
    or call [`perfetto_view`](@ref) on profile data you collected yourself.

# Calibration options
Trailing `key = value` arguments tune the calibration loop:

- `initial_delay::Float64` (default `0.01`, i.e. 10 ms) — sampling delay
  used for the first calibration round. The first round is meant to be
  coarse and cheap; it just measures how long `expr` takes.
- `min_delay::Float64` (default `1e-7`, i.e. 0.1 μs) — hard floor on the
  sampling delay. Raise it if you see huge profile overhead on very fast
  workloads.
- `buffer_slots::Int` (default `10_000_000`, ~80 MB) — size of the profile
  sample buffer. The loop targets ~50 % fill; bump this if traces get
  truncated.
- `max_rounds::Int` (default `6`) — maximum number of times `expr` is run.
  Lower this if you want fewer repetitions.
- `max_inflation::Float64` (default `10.0`) — largest allowed ratio of
  measured wall time to the overhead-free baseline. Calibration backs off
  the sampling delay so profiler overhead can't blow runtime up by more
  than this factor.
- `max_step::Float64` (default `8.0`) — maximum factor by which the delay
  is allowed to shrink between consecutive rounds.

# Example
```julia
using ProfilePerfetto

@perfetto my_expensive_function(args...)

# Cap calibration at 4 rounds and don't sharpen below 10 μs:
@perfetto my_expensive_function(args...) max_rounds=4 min_delay=1e-5
```

See also [`@perfetto_open`](@ref) for opening the chart in a browser, and
[`perfetto_view`](@ref) / [`perfetto_open`](@ref) for visualizing profile
data you collected yourself.
"""
macro perfetto_view(expr, kw_args...)
    _perfetto_macro(:perfetto_view, expr, kw_args, "@perfetto")
end

const var"@perfetto" = var"@perfetto_view"

"""
    @perfetto_open expr [key=value ...]

Like [`@perfetto`](@ref), but opens the resulting flame chart in your default
web browser instead of rendering inline. Use this from the plain Julia REPL.

The expression is executed **multiple times** as part of automatic sampling
rate calibration; see [`@perfetto`](@ref) for details and for the list of
accepted `key = value` calibration options.
"""
macro perfetto_open(expr, kw_args...)
    _perfetto_macro(:perfetto_open, expr, kw_args, "@perfetto_open")
end
