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
