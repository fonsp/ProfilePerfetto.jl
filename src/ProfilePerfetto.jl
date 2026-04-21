module ProfilePerfetto

export @perfetto, perfetto_view, perfetto_open

import Profile
import JSON
import Base64
import Dates

### ---- Workload sentinel
#
# The macro runs the user's expression through this funny-named function so we
# can identify the workload in the raw stack trace and discard everything above
# it (REPL, eval machinery, task scheduler, etc.). Frames strictly below this
# one in the call stack are the user code we want to display.
const _SENTINEL_NAME = "🐔🚀🧦"

🐔🚀🧦(f::Function) = f()

const _PERFETTO_TIPS = [
    "Use <kbd>W</kbd>/<kbd>S</kbd> to zoom in and out, and <kbd>A</kbd>/<kbd>D</kbd> to pan left and right.",
    "Press <kbd>/</kbd> to search across all slices and threads by name.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Drag on the time ruler at the top to select a time range — the details panel then shows aggregated stats for the selection.",
    "Click a slice, then press <kbd>M</kbd> to mark its timespan so it stays highlighted as you navigate.",
    "Hold <kbd>Shift</kbd> and scroll to zoom smoothly around the mouse cursor.",
    "Pin a track by clicking the pin icon on its left edge to keep it visible while scrolling.",
    "The <strong>Flame Graph</strong> tab at the bottom aggregates the current selection into a single flame chart.",
    "Right-click a slice and choose <em>Show in Query</em> to explore the trace with SQL.",
    "Use <kbd>Ctrl</kbd>+<kbd>F</kbd> (or <kbd>⌘</kbd>+<kbd>F</kbd>) to re-focus the search box at any time.",
    "You can drop any Perfetto trace file onto the Perfetto window to open it — great for comparing profiles.",
    "Slices are colored by name: functions with the same name share a color, which helps spot hot code paths.",
    "Double-click a slice to zoom the timeline to exactly its extent.",
]

### ---- Sample parsing

# One sample with per-thread metadata, as produced by Profile.fetch(; include_meta = true).
#
# Raw buffer layout per sample (see Julia stdlib Profile.jl — the `0, 0` pair is the
# block-end marker; a single `0` in the ips is a valid rogue null IP on some platforms):
#
#   ips..., thread_id, task_id, cpu_cycle_clock, sleepstate, 0, 0
#
# Offsets (from the trailing 0 at index `i`):
#   i-5 = thread_id,  i-4 = task_id,  i-3 = cpu_cycle_clock,  i-2 = sleepstate
struct Sample
    stack::Vector{UInt64}    # instruction pointers, leaf-first
    thread_id::UInt64
    task_id::UInt64
    timestamp_ns::UInt64     # from jl_hrtime(), monotonic
    sleepstate::UInt64       # 1 = awake, 2 = sleeping, 3 = task-profiler fake
end

function _parse_samples(data::Vector{UInt64})
    samples = Sample[]
    n = length(data)
    sample_start = 1
    i = 6  # need i-5 to be a valid index
    while i <= n
        # A block-end is two consecutive zeros — but a rogue single zero IP can
        # appear, so also require a non-zero sleepstate just before it.
        if data[i] == 0 && data[i-1] == 0 && data[i-2] != 0
            thread_id = data[i-5]
            task_id = data[i-4]
            cpu_cycle = data[i-3]
            sleepstate = data[i-2]
            ips = data[sample_start:(i-6)]
            push!(samples, Sample(ips, thread_id, task_id, cpu_cycle, sleepstate))
            sample_start = i + 1
            i = sample_start + 5
        else
            i += 1
        end
    end
    return samples
end

# Flatten one sample's ips into a top-down list of (name, file, line) frames.
# When `filter_sentinel` is true, the result is truncated to only the frames
# strictly below `_SENTINEL_NAME`; samples that don't contain the sentinel at
# all return an empty vector.
function _stack_frames(
    stack::Vector{UInt64}, lidict; C::Bool = false, filter_sentinel::Bool = false
)
    result = Tuple{String,String,Int}[]
    # Raw stack is leaf-first; iterate in reverse for root-first (top-down).
    for ip in Iterators.reverse(stack)
        frames = get(lidict, ip, nothing)
        if frames === nothing
            push!(result, ("ip_0x$(string(ip; base = 16))", "", 0))
            continue
        end
        # Each ip may correspond to multiple (inlined) StackFrames,
        # stored innermost-first. Reverse for top-down order.
        for sf in Iterators.reverse(frames)
            if !C && sf.from_c
                continue
            end
            push!(result, (string(sf.func), string(sf.file), sf.line))
        end
    end
    if filter_sentinel
        idx = findfirst(f -> f[1] == _SENTINEL_NAME, result)
        idx === nothing && return Tuple{String,String,Int}[]
        return result[(idx+1):end]
    end
    return result
end

### ---- Perfetto JSON generation

# Walk through samples per thread in timestamp order and emit Begin/End events
# such that adjacent samples sharing a common stack prefix merge into a span.
function _samples_to_perfetto_json(
    data::Vector{UInt64},
    lidict;
    sample_interval_us::Float64 = 1000.0,
    filter_sentinel::Bool = false,
)
    samples = _parse_samples(data)
    events = Any[]
    isempty(samples) && return JSON.json(
        Dict(
            "traceEvents" => events,
            "metadata" => Dict(
                "clock-domain" => "MONO",
                "command_line" => "Julia Profile",
            ),
        ),
    )

    # Group by thread and sort by real ns timestamp so each thread has a
    # contiguous sample stream, independent of interleaving in the raw buffer.
    by_thread = Dict{UInt64,Vector{Sample}}()
    for s in samples
        push!(get!(by_thread, s.thread_id, Sample[]), s)
    end
    for v in values(by_thread)
        sort!(v; by = s -> s.timestamp_ns)
    end

    # Normalize timestamps so the earliest sample across all threads sits at t=0.
    t0 = minimum(s.timestamp_ns for s in samples)

    for (tid, thread_samples) in by_thread
        stacks = [
            _stack_frames(s.stack, lidict; filter_sentinel) for s in thread_samples
        ]
        ts_us = [Float64(Int64(s.timestamp_ns) - Int64(t0)) / 1000 for s in thread_samples]

        prev = Tuple{String,String,Int}[]
        last_t::Float64 = 0.0
        for (stack, t) in zip(stacks, ts_us)
            last_t = t
            # When `filter_sentinel` drops everything, the sampler either caught
            # the sentinel itself executing or a stack unrelated to the workload.
            # Treat these as "nothing interesting to show" — keep prev open so
            # the span doesn't needlessly fragment.
            isempty(stack) && continue
            # Merge on (name, file) only — the `line` of a non-leaf frame is
            # the current call-site inside that function, which drifts as the
            # function hits different sub-expressions and would otherwise
            # needlessly split one span into many.
            k = 0
            while k < length(stack) &&
                      k < length(prev) &&
                      stack[k+1][1] == prev[k+1][1] &&
                      stack[k+1][2] == prev[k+1][2]
                k += 1
            end
            for j in length(prev):-1:(k+1)
                push!(
                    events,
                    Dict(
                        "ph" => "E",
                        "pid" => 1,
                        "tid" => tid,
                        "ts" => t,
                        "name" => prev[j][1],
                    ),
                )
            end
            for j in (k+1):length(stack)
                name, file, line = stack[j]
                push!(
                    events,
                    Dict(
                        "ph" => "B",
                        "pid" => 1,
                        "tid" => tid,
                        "ts" => t,
                        "name" => name,
                        "args" => Dict("file" => file, "line" => line),
                    ),
                )
            end
            prev = stack
            last_t = t
        end
        # Close anything still open — extend by one sample interval so the
        # final span is visible rather than zero-width.
        final_t = last_t + sample_interval_us
        for j in length(prev):-1:1
            push!(
                events,
                Dict(
                    "ph" => "E",
                    "pid" => 1,
                    "tid" => tid,
                    "ts" => final_t,
                    "name" => prev[j][1],
                ),
            )
        end
    end

    return JSON.json(
        Dict(
            "traceEvents" => events,
            "metadata" => Dict(
                "clock-domain" => "MONO",
                "command_line" => "Julia Profile",
            ),
        ),
    )
end

function _profile_delay_us()::Float64
    try
        Float64(ccall(:jl_profile_delay_nsec, UInt64, ())) / 1000
    catch
        1000.0
    end
end

function _default_name()
    return "$(Dates.Time(Dates.now())) Julia profile"
end

### ---- Display functionality (pattern reused from RxInfer's perfetto.jl)

"""
    PerfettoDisplay

Returned by [`perfetto_view`](@ref). Renders as an embedded
[Perfetto](https://ui.perfetto.dev) trace viewer when displayed in a
Pluto, VS Code or Jupyter notebook cell.
"""
struct PerfettoDisplay
    html::String
end

function Base.show(io::IO, ::MIME"text/html", p::PerfettoDisplay)
    print(io, p.html)
end

function Base.show(io::IO, ::MIME"juliavscode/html", p::PerfettoDisplay)
    show(io, MIME"text/html"(), p)
end

Base.show(io::IO, ::PerfettoDisplay) = print(
    io,
    "PerfettoDisplay (render in a Pluto, VS Code or Jupyter notebook to see the interactive trace)",
)

function _overlay_html()
    tip = rand(_PERFETTO_TIPS)
    return """<style>
          @keyframes pp-shimmer {
            0%   { background-position: 0% 50%; }
            50%  { background-position: 100% 50%; }
            100% { background-position: 0% 50%; }
          }
          @keyframes pp-bounce {
            0%, 80%, 100% { transform: translateY(0);     opacity: 0.4; }
            40%           { transform: translateY(-0.4em); opacity: 1;   }
          }
          @keyframes pp-fadein {
            from { opacity: 0; transform: translateY(6px); }
            to   { opacity: 1; transform: translateY(0);   }
          }
          #overlay {
            position: fixed; top: 0; left: 0; width: 100vw; height: 100vh;
            display: flex; align-items: center; justify-content: center;
            background: linear-gradient(120deg,
              rgba(255,255,255,0.85), rgba(235,240,255,0.85),
              rgba(255,240,245,0.85), rgba(255,255,255,0.85));
            background-size: 300% 300%;
            animation: pp-shimmer 6s ease-in-out infinite;
            transition: opacity 0.4s ease;
            font-family: system-ui, -apple-system, sans-serif;
          }
          #overlay .card {
            text-align: left; animation: pp-fadein 0.5s ease both;
            color: #000;
          }
          #overlay .title {
            font: bold 3rem system-ui; white-space: nowrap;
            animation: pp-shimmer 3s linear infinite;
          }
          #overlay .dot {
            display: inline-block; width: 0.5em; height: 0.5em;
            margin: 0 0.08em; border-radius: 50%; background: #6ea96a;
            animation: pp-bounce 1.2s ease-in-out infinite;
          }
          #overlay .dot:nth-child(2) { animation-delay: 0.15s; background: #9f83b8; }
          #overlay .dot:nth-child(3) { animation-delay: 0.30s; background: #c97b73; }
          #overlay .hint {
            margin-top: 0.3em; font: 1rem system-ui; opacity: 0.75;
            color: #000;
          }
          #overlay .tip {
            margin-top: 1.8em; max-width: 34em;
            font: 0.95rem system-ui; color: #333;
            padding: 0.8em 1em; border-left: 3px solid #6a5acd;
            background: rgba(255,255,255,0.6); border-radius: 4px;
          }
          #overlay .tip-label {
            font-size: 0.75rem; letter-spacing: 0.12em;
            text-transform: uppercase; color: #6a5acd; font-weight: 600;
            margin-bottom: 0.3em;
          }
          kbd {
            color: black;
          }
        </style>
        <div id="overlay">
          <div class="card">
            <span class="title">Loading</span><span class="title"
              ><span class="dot"></span><span class="dot"></span><span class="dot"></span></span>
            <div class="hint">Click <strong>Yes</strong> in the next dialog</div>
            <div class="tip">
              <div class="tip-label">Perfetto tip</div>
              $(tip)
            </div>
          </div>
        </div>"""
end

"""
    perfetto_view(data = Profile.fetch(; include_meta = false),
                         lidict = Profile.getdict(data);
                         name = "Julia profile")

Converts Julia profile sample data to an embedded [Perfetto](https://ui.perfetto.dev)
trace viewer. Returns a [`PerfettoDisplay`](@ref) that renders as an interactive
trace when displayed in a Pluto, VS Code or Jupyter notebook cell.

See also: [`@perfetto`](@ref), [`perfetto_open`](@ref).
"""
function perfetto_view(
    data::Vector{UInt64} = Profile.fetch(; include_meta = true),
    lidict = Profile.getdict(data);
    name::String = _default_name(),
    filter_sentinel::Bool = false,
)
    json_contents = _samples_to_perfetto_json(
        data,
        lidict;
        sample_interval_us = _profile_delay_us(),
        filter_sentinel,
    )
    b64 = Base64.base64encode(json_contents)
    id = String(rand('a':'z', 10))
    html = """
        <div style="width: 100%; height: clamp(650px, 90vh, 1000px);">
        <iframe id="$id" src="https://ui.perfetto.dev"
          style="width:100%;height:100%;border:7px solid yellow;border-radius: 12px; box-sizing: border-box;"></iframe>
          $(_overlay_html())
        <script>
        const b64 = "$b64";
        const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
        const iframe = document.getElementById('$id');
        const overlay = document.getElementById('overlay');

        const interval = setInterval(() => {
          iframe.contentWindow.postMessage('PING', 'https://ui.perfetto.dev');
        }, 50);

        window.addEventListener('message', (e) => {
          if (e.data !== 'PONG') return;
          clearInterval(interval);
          iframe.contentWindow.postMessage({
            perfetto: {
              buffer: bytes.buffer,
              title: "$(name)",
            }
          }, 'https://ui.perfetto.dev');
          setTimeout(() => {
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 400);
          }, 300);
        });
        </script>
        </div>"""
    return PerfettoDisplay(html)
end

"""
    perfetto_open(data = Profile.fetch(; include_meta = false),
                         lidict = Profile.getdict(data);
                         name = "Julia profile")

Opens the current Julia profile in the default web browser using the
[Perfetto](https://ui.perfetto.dev) trace viewer. Returns the path to the
temporary HTML file that was opened.
"""
function perfetto_open(
    data::Vector{UInt64} = Profile.fetch(; include_meta = true),
    lidict = Profile.getdict(data);
    name::String = _default_name(),
    filter_sentinel::Bool = false,
)
    json_contents = _samples_to_perfetto_json(
        data,
        lidict;
        sample_interval_us = _profile_delay_us(),
        filter_sentinel,
    )
    b64 = Base64.base64encode(json_contents)
    html = """<!DOCTYPE html><html><body style="margin:0">
        <iframe id="pf" src="https://ui.perfetto.dev"
          style="width:100vw;height:100vh;border:none;position:fixed;top:0;left:0"></iframe>
        $(_overlay_html())
        <script>
        const b64 = "$b64";
        const bytes = Uint8Array.from(atob(b64), c => c.charCodeAt(0));
        const iframe = document.getElementById('pf');
        const overlay = document.getElementById('overlay');

        const interval = setInterval(() => {
          iframe.contentWindow.postMessage('PING', 'https://ui.perfetto.dev');
        }, 50);

        window.addEventListener('message', (e) => {
          if (e.data !== 'PONG') return;
          clearInterval(interval);
          iframe.contentWindow.postMessage({
            perfetto: {
              buffer: bytes.buffer,
              title: "$(name)",
            }
          }, 'https://ui.perfetto.dev');
          setTimeout(() => {
            overlay.style.opacity = '0';
            setTimeout(() => overlay.remove(), 400);
          }, 300);
        });
        </script>
        </body></html>"""
    filename = tempname(; cleanup = false) * ".html"
    write(filename, html)
    if Sys.isapple()
        run(`open $filename`)
    elseif Sys.iswindows()
        run(`cmd /c start "" $filename`)
    elseif Sys.islinux()
        run(`xdg-open $filename`)
    else
        @info "Open this in your browser: $filename"
    end
    return filename
end

### ---- The macro

"""
    @perfetto expr

Profiles `expr` using Julia's built-in `Profile` stdlib and returns a
[`PerfettoDisplay`](@ref) that renders the samples as an interactive
[Perfetto](https://ui.perfetto.dev) flame chart when shown in a Pluto,
VS Code or Jupyter notebook.

Existing profile data is cleared before running `expr`.

# Example
```julia
using ProfilePerfetto

@perfetto my_expensive_function(args...)
```
"""
macro perfetto(expr)
    quote
        Profile.clear()
        Profile.@profile 🐔🚀🧦(() -> $(esc(expr)))
        data, lidict = Profile.retrieve(; include_meta = true)
        perfetto_view(data, lidict; filter_sentinel = true)
    end
end

end # module
