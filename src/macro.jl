### ---- The macro


function _perfetto_macro(f, expr)
    quote
        # Clear
        Profile.clear()
        local _t0 = time_ns()
        
        # Run user code
        Profile.@profile 🐔🚀🧦(() -> $(esc(expr)))
        
        # Process
        local _wall_ns = time_ns() - _t0
        data, lidict = Profile.retrieve(; include_meta = true)
        
        # Show data
        $(f)(data, lidict; filter_sentinel = true, wall_time_ns = _wall_ns)
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
