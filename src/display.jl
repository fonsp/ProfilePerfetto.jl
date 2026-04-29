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
    "PerfettoDisplay (to render in a Pluto, VS Code or Jupyter notebook to see the interactive trace).\n\nSeeing this in the REPL? Use `@perfetto_open` instead to open the trace in a web browser.",
)


const _PERFETTO_TIPS = [
    "Use <kbd>W</kbd>/<kbd>S</kbd> to zoom in and out, and <kbd>A</kbd>/<kbd>D</kbd> to pan left and right.",
    "Use <kbd>W</kbd>/<kbd>S</kbd> to zoom in and out, and <kbd>A</kbd>/<kbd>D</kbd> to pan left and right.",
    "Use <kbd>W</kbd>/<kbd>S</kbd> to zoom in and out, and <kbd>A</kbd>/<kbd>D</kbd> to pan left and right.",
    "Use <kbd>W</kbd>/<kbd>S</kbd> to zoom in and out, and <kbd>A</kbd>/<kbd>D</kbd> to pan left and right.",
    "Press <kbd>/</kbd> to search across all slices and threads by name.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
    "Press <kbd>?</kbd> inside Perfetto to see the full list of keyboard shortcuts.",
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
            position: absolute; 
            top: 0; 
            left: 0; 
            right: 0; 
            bottom: 0;
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
            background: white; 
            border-radius: 4px;
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
