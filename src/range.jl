"""
    range(x) -> AbstractRange

Construct a range from a scalar or a range.
"""
function range end

range(i::Integer) = i:i
range(p::Period) = p:oneunit(p):p
range(r::AbstractRange) = r
