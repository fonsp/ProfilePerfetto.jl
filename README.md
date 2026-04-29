# ProfilePerfetto.jl

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](http://fonsp.github.io/ProfilePerfetto.jl/stable/)

The goal of this package is to give a super-simple-to-use profiling tool, but still provide a nice UI with some features like a flame chart.

Use ProfilePerfetto.jl to view Julia profiles as an interactive [Perfetto](https://perfetto.dev) trace/flame chart. You can view a profile directly in Pluto, VS Code and Jupyter. Or launch Perfetto in your default browser from the REPL.

# Example
To create a profile and view it directly:

```julia
using ProfilePerfetto

@perfetto my_expensive_function(args...)
```

![Perfetto traces](docs/src/assets/perfetto%20traces.png)

# Video showcase
In this video, you see some of the features of Perfetto in action.

https://github.com/user-attachments/assets/be74a099-0ab1-4b71-9fb3-44e3925083f2


# Written by AI
This package was vibe coded by Fons, using Claude Code. 