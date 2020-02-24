module ReverseDiffExpressions

# using VectorizationBase, SIMDPirates
# using StackPointers, LinearAlgebra, PaddedMatrices#, StructuredMatrices, ProbabilityDistributions, Parameters
using LoopVectorization, Parameters
using LoopVectorization: Instruction, LoopSet

export Target

# using PaddedMatrices:
    # AbstractFixedSizeVector, AbstractMutableFixedSizeVector, UninitializedVector,
    # AbstractFixedSizeMatrix, AbstractMutableFixedSizeMatrix, UninitializedMatrix,
    # AbstractFixedSizeArray, AbstractMutableFixedSizeArray, UninitializedArray

# using StructuredMatrices: AbstractLowerTriangularMatrix
# using ProbabilityDistributions: distribution_diff_rule!

# using FunctionWrappers: FunctionWrapper
# using MacroTools: postwalk, prewalk, @capture, @q

# import SIMDPirates: vsum, vadd, vifelse
# import ReverseDiffExpressionsBase: adj, ∂mul, ∂getindex, RESERVED_INCREMENT_SEED_RESERVED!,
    # InitializedVarTracker, add_aliases!, allocate!, initialize!, isallocated, deallocate!

# FIXME: create it; stub for now

const STACK_POINTER_NAME = Symbol("###STACK##POINTER###")

struct Target{W,T}
    v::NTuple{W,Core.VecElement{T}}
end
@inline Target() = Target(LoopVectorization.SIMDPirates.extract_data(LoopVectorization.vbroadcast(LoopVectorization.pick_vector_width_val(Float64), 0.0)))
@inline Target(::Type{T}) where {T} = Target(LoopVectorization.SIMDPirates.extract_data(LoopVectorization.vbroadcast(LoopVectorization.pick_vector_width_val(T), zero(T))))
@inline Base.:(+)(t::Target, s) = Target(LoopVectorization.addscalar(t.v, s))
@inline Base.:(+)(s, t::Target) = Target(LoopVectorization.addscalar(t.v, s))
@inline Base.:(+)(t::Target{WT,T}, v::LoopVectorization.SVec{WV,T}) where {WT,WV,T} = Target(LoopVectorization.vadd(t.v, LoopVectorization.SIMDPirates.extract_data(v)))
@inline Base.:(+)(t::Target{WT,T}, v::NTuple{WV,Core.VecElement{T}}) where {WT,WV,T} = Target(LoopVectorization.vadd(t.v, v))
@inline Base.:(+)(v::LoopVectorization.SVec{WV,T}, t::Target{WT,T}) where {WT,WV,T} = Target(LoopVectorization.vadd(t.v, LoopVectorization.SIMDPirates.extract_data(v)))
@inline Base.:(+)(v::NTuple{WV,Core.VecElement{T}}, t::Target{WT,T}) where {WT,WV,T} = Target(LoopVectorization.vadd(t.v, v))
@inline Base.:(+)(t₁::Target, t₂::Target) = Target(LoopVectorization.vadd(t₁.v, t₂.v))
@inline Base.sum(t::Target) = LoopVectorization.vsum(t.v)


include("variables.jl")
include("funcs.jl")
include("models.jl")
include("tracking_description.jl")
include("loopsets/loopset_gradients.jl") # defines a module that includes the other loopsets/*.jl files
include("differentiate.jl")
include("lowering.jl")
# include("adjoints.jl")
# include("misc_functions.jl")
# include("special_diff_rules.jl")
# include("reverse_autodiff_passes.jl")

# include("precompile.jl")
# _precompile_()

# @def_stackpointer_fallback emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
function __init__()
    # @add_stackpointer_method emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
end

end # module
