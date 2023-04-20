module MockTableGenerators

using Dates: Period
using Random: AbstractRNG

export TableGenerator

include("generate.jl")
include("range.jl")

end # module
