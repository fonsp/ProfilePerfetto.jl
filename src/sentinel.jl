### ---- Workload sentinel
#
# The macro runs the user's expression through this funny-named function so we
# can identify the workload in the raw stack trace and discard everything above
# it (REPL, eval machinery, task scheduler, etc.). Frames strictly below this
# one in the call stack are the user code we want to display.
const _SENTINEL_NAME = "🐔🚀🧦"

🐔🚀🧦(f::Function) = f()
