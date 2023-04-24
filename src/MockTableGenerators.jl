module MockTableGenerators

using Dates: Period
using Random: AbstractRNG, GLOBAL_RNG

export TableGenerator

include("generate.jl")
include("range.jl")

end # module
