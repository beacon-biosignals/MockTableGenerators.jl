module MockTableGenerators

using Dates: Period

export TableGenerator

include("generate.jl")
include("range.jl")

end # module
