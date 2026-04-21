### ---- The macro


function _perfetto_macro(f, expr)
    quote
        Profile.clear()
        Profile.@profile 🐔🚀🧦(() -> $(esc(expr)))
        data, lidict = Profile.retrieve(; include_meta = true)
        $(f)(data, lidict; filter_sentinel = true)
    end
end

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
macro perfetto_view(expr)
    _perfetto_macro(:perfetto_view, expr)
end

const var"@perfetto" = var"@perfetto_view"

"""
    @perfetto_open expr

Profiles `expr` using Julia's built-in `Profile` stdlib and opens the
resulting [Perfetto](https://ui.perfetto.dev) flame chart in a web browser.

Existing profile data is cleared before running `expr`.

# Example
```julia
using ProfilePerfetto

@perfetto_open my_expensive_function(args...)
```
"""
macro perfetto_open(expr)
    _perfetto_macro(:perfetto_open, expr)
end
