using Documenter
using MockTableGenerators

makedocs(; modules=[MockTableGenerators],
         sitename="MockTableGenerators.jl",
         authors="Beacon Biosignals, Inc.",
         pages=["API Documentation" => "index.md"])

deploydocs(; repo="github.com/beacon-biosignals/MockTableGenerators.jl.git")
