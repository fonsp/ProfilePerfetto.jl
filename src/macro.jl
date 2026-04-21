### ---- The macro


function _perfetto_macro(f, expr)
    # We drive `Profile.Allocs` via its `start`/`stop` functions rather than its
    # `@profile` macro: the macro takes `sample_rate` as a keyword-like arg, but
    # Julia's hygiene pass renames that symbol when the call is nested inside
    # our own `quote` block, causing `UndefKeywordError: sample_rate`.
    quote
        Profile.clear()
        Profile.Allocs.clear()
        Profile.Allocs.start(; sample_rate = 0.01)
        local _t0 = time_ns()
        try
            Profile.@profile 🐔🚀🧦(() -> $(esc(expr)))
        finally
            Profile.Allocs.stop()
        end
        local _wall_ns = time_ns() - _t0
        data, lidict = Profile.retrieve(; include_meta = true)
        local _allocs = Profile.Allocs.fetch()
        $(f)(
            data,
            lidict;
            filter_sentinel = true,
            wall_time_ns = _wall_ns,
            alloc_results = _allocs,
        )
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
