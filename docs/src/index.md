# ProfilePerfetto.jl

*Profile your Julia code and view the results in a beautiful, interactive flame chart.* 🔥

```@raw html
<p><img alt="Screenshot of a Perfetto traces" src="./assets/perfetto traces.png" style="max-width: 500px"></p>
```

ProfilePerfetto.jl is a tiny bridge between Julia's built-in
[`Profile`](https://docs.julialang.org/en/v1/stdlib/Profile/) standard library
and the [Perfetto](https://ui.perfetto.dev) trace viewer — the same tool used
for analyzing Chrome and Android performance traces.

If you've never profiled Julia code before: **don't worry**. By the end of
the [Getting started](@ref) page, you'll have your first flame chart on screen.

## Why profile?

Your code is slow. You have a hunch about why. You're probably wrong. 😉

A profiler samples your program many times per second and records *what
function is currently running*. After a few seconds of sampling, the most
frequently-seen functions are almost certainly your bottleneck — no guessing
required.

## A 30-second example

```julia
using ProfilePerfetto

function slow_thing()
    x = 0.0
    for i in 1:10_000_000
        x += sin(i) * cos(i)
    end
    return x
end

@perfetto slow_thing()
```

Run that cell in **Pluto**, **VS Code**, or **Jupyter**, and you'll see an
interactive flame chart appear right below it. Drag to pan, scroll to zoom,
click on a bar to see the file and line number.

`@perfetto` automatically calibrates the sampling rate for you — there's no
`delay` knob to tune. The trade-off: it runs your code a few times to do so.

!!! warning "Your code runs multiple times"
    `@perfetto` evaluates the expression several times while calibrating. If
    it has observable side effects (mutating state, I/O, network calls),
    wrap the workload in something idempotent first, or hand pre-collected
    profile data to [`perfetto_view`](@ref).

!!! tip "Not in a notebook?"
    From the plain Julia REPL, use [`@perfetto_open`](@ref) instead — it
    opens the chart in your default browser.

## What's next?

- [Getting started](@ref) — a friendly walk-through for anyone new to profiling.
- [Tuning the profiler](@ref) — calibration knobs and how to feed in your own
  profile data.
- [API reference](@ref) — every exported name, spelled out.
