using Documenter
using Documenter: Remotes
using ProfilePerfetto

DocMeta.setdocmeta!(
    ProfilePerfetto,
    :DocTestSetup,
    :(using ProfilePerfetto);
    recursive = true,
)

makedocs(;
    modules = [ProfilePerfetto],
    sitename = "ProfilePerfetto.jl",
    authors = "Fons van der Plas <fons@plutojl.org>",
    repo = Remotes.GitHub("fonsp", "ProfilePerfetto.jl"),
    format = Documenter.HTML(;
        prettyurls = get(ENV, "CI", "false") == "true",
        canonical = "https://fonsp.github.io/ProfilePerfetto.jl",
        edit_link = "main",
    ),
    pages = [
        "Home" => "index.md",
        "Getting started" => "getting-started.md",
        "Tuning the profiler" => "tuning.md",
        "API reference" => "api.md",
    ],
    warnonly = [:missing_docs, :cross_references],
)

deploydocs(;
    repo = "github.com/fonsp/ProfilePerfetto.jl",
    devbranch = "main",
)
