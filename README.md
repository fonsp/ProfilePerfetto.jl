# ProfilePerfetto.jl

[![Docs](https://img.shields.io/badge/docs-stable-blue.svg)](http://fonsp.github.io/ProfilePerfetto.jl/stable/)

View Julia profiles as an interactive [Perfetto](https://ui.perfetto.dev) flame chart. You can view a profile directly in Pluto, VS Code and Jupyter. Or launch Perfetto in your default browser from the REPL.

```julia
using ProfilePerfetto

@perfetto my_expensive_function(args...)
```

![Perfetto traces](docs/src/assets/perfetto%20traces.png)

# Video showcase
In this video, you see some of the features of Perfetto in action.


https://github.com/user-attachments/assets/be74a099-0ab1-4b71-9fb3-44e3925083f2

