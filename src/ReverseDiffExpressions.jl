module ReverseDiffExpressions

using FunctionWrappers, PaddedMatrices, StackPointers

import SIMDPirates: vsum, vadd, vifelse


export Zero, One

"""
Additive identity.
"""
struct Zero end
@inline Base.+(a::Zero, b) = b
@inline Base.+(a, b::Zero) = a
@inline Base.+(a::Zero, b::Zero) = Zero()
@inline Base.+(sptr::StackPointer, a::Zero, b) = (sptr, b)
@inline Base.+(sptr::StackPointer, a, b::Zero) = (sptr, a)
@inline Base.+(sptr::StackPointer, a::Zero, b::Zero) = (sptr, Zero())
"""
Multiplicative identity.
"""
struct One end
@inline Base.*(a::One, b) = b
@inline Base.*(a, b::One) = a
@inline Base.*(a::One, b::One) = One()
@inline Base.*(sptr::StackPointer, a::One, b) = (sptr, b)
@inline Base.*(sptr::StackPointer, a, b::One) = (sptr, a)
@inline Base.*(sptr::StackPointer, a::One, b::One) = (sptr, One())

Base.size(::Zero) = Core.tuple()
Base.size(::One) = Core.tuple()

include("target.jl")
include("seed_increments.jl")

end # module
