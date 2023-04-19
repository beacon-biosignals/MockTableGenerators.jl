module MockTableGenerators

using Dates: Period
using Random

export TableGenerator

include("generate.jl")
include("range.jl")

end # module
