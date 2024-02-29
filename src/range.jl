"""
    range(x) -> AbstractRange

Constructs a single-element range from a scalar, or returns the given range.

# Examples
julia> MockTableGenerators.range(3)
3:3

julia> MockTableGenerators.range(Minute(3))
Minute(3):Minute(1):Minute(3)

julia> MockTableGenerators.range(1:10)
1:10
"""
function range end

range(i::Integer) = i:i
range(p::Period) = p:oneunit(p):p
range(r::AbstractRange) = r
