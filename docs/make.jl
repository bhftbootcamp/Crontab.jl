using Crontab
using Documenter

DocMeta.setdocmeta!(Crontab, :DocTestSetup, :(using Crontab); recursive = true)

makedocs(;
    modules = [Crontab],
    sitename = "Crontab.jl",
    format = Documenter.HTML(;
        repolink = "https://github.com/bhftbootcamp/Crontab.jl",
        canonical = "https://bhftbootcamp.github.io/Crontab.jl",
        edit_link = "master",
        assets = ["assets/favicon.ico"],
        sidebar_sitename = true,
    ),
    pages = [
        "Home"    => "index.md",
        "pages/api_reference.md",
    ],
    warnonly = [:doctest, :missing_docs],
    repo = "github.com/bhftbootcamp/Crontab.jl"
)

deploydocs(;
    repo = "github.com/bhftbootcamp/Crontab.jl",
    devbranch = "master",
    push_preview = true,
)
