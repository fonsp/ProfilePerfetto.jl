# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this package does

ProfilePerfetto.jl converts Julia's built-in `Profile` stdlib sample data into a [Perfetto](https://ui.perfetto.dev) trace and embeds the Perfetto UI in an iframe (Pluto / VS Code / Jupyter) or opens it in the browser. The user-facing API is `@perfetto_view` (alias `@perfetto`), `@perfetto_open`, `perfetto_view`, and `perfetto_open`.

## Commands

Run tests:
```
julia --project=. -e 'using Pkg; Pkg.test()'
```

Run a single testset — `runtests.jl` uses plain `@testset` blocks with no per-test filtering infrastructure, so pass a name filter to `Pkg.test` is not supported; instead run the file directly and comment out unwanted testsets, or `julia --project=. test/runtests.jl`.

Build docs:
```
julia --project=docs docs/make.jl
```

## Architecture

The pipeline is linear: raw profile buffer → parsed samples → per-thread Perfetto trace-event JSON → embedded HTML viewer.

1. **`samples.jl` — raw buffer parsing.** `Profile.fetch(; include_meta=true)` returns a flat `Vector{UInt64}` where each sample is `ips..., thread_id, task_id, cpu_cycle_clock, sleepstate, 0, 0`. `_parse_samples` walks this with a **two-zero block-end marker plus non-zero sleepstate guard** because a single `0` IP can legitimately appear mid-stack on some platforms. Changes to the layout assumptions must preserve this guard.

2. **`sentinel.jl` — the workload boundary.** The `@perfetto` macro runs the user expression through a function literally named `🐔🚀🧦`. `_stack_frames(...; filter_sentinel=true)` discards everything at-or-above this frame so REPL/eval/scheduler noise disappears. If you rename or remove the sentinel, update `_SENTINEL_NAME` in lockstep — the macro expansion and the filter rely on the exact same identifier.

3. **`json.jl` — span merging.** Rather than emitting one B/E pair per sample per frame, consecutive samples on the same thread merge on `(name, file)` prefix into a single span. The `line` is intentionally *not* part of the merge key: the line on a non-leaf frame is the current call-site, which drifts as the function advances. Merging on line would shatter one span into many. When `filter_sentinel` drops a sample entirely (sampler caught the sentinel itself or unrelated stack), `prev` is kept open so the enclosing span doesn't fragment. The final open spans are closed `sample_interval_us` past the last timestamp so they're visible rather than zero-width.

4. **`view.jl` / `display.jl` — delivery.** The JSON is base64'd into an HTML string that posts a `PING`/`PONG` handshake to the `ui.perfetto.dev` iframe, then posts the trace buffer. `PerfettoDisplay` implements both `text/html` and `juliavscode/html` MIME so it renders in Pluto, Jupyter, and VS Code. `perfetto_open` writes the same HTML to a tempfile and shells out to `open` / `start` / `xdg-open`.

5. **`macro.jl` — entry point.** `@perfetto` clears existing profile state, wraps the expression in the sentinel, calls `Profile.retrieve(; include_meta=true)`, and hands off to `perfetto_view` with `filter_sentinel=true`.

## Things to watch out for

- **Don't hallucinate Julia package UUIDs** in `Project.toml`. Leave `[deps]` additions empty and let `Pkg.add` fill in real UUIDs.
- `Profile.fetch` must be called with `include_meta = true` — the parser depends on the metadata trailer. `perfetto_view`'s default argument reflects this (note: the docstring shows `include_meta = false`, which is stale — the actual default is `true`).
- The sentinel is a valid Julia identifier made of emoji. Tools that mangle non-ASCII identifiers will silently break the filter.
