using Documenter, ReverseDiffExpressions

makedocs(;
    modules=[ReverseDiffExpressions],
    format=Documenter.HTML(),
    pages=[
        "Home" => "index.md",
    ],
    repo="https://github.com/chriselrod/ReverseDiffExpressions.jl/blob/{commit}{path}#L{line}",
    sitename="ReverseDiffExpressions.jl",
    authors="Chris Elrod",
    assets=String[],
)

deploydocs(;
    repo="github.com/chriselrod/ReverseDiffExpressions.jl",
)
