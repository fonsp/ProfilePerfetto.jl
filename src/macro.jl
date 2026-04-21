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
