module ReverseDiffExpressions

using VectorizationBase, StackPointers, SIMDPirates, DiffRules, LinearAlgebra, PaddedMatrices, StructuredMatrices, ProbabilityDistributions

using PaddedMatrices:
    AbstractFixedSizeVector,
    AbstractFixedSizeMatrix,
    AbstractMutableFixedSizeArray

using StructuredMatrices: AbstractLowerTriangularMatrix
using ProbabilityDistributions: distribution_diff_rule!

using FunctionWrappers: FunctionWrapper
using MacroTools: postwalk, prewalk, @capture, @q

# import SIMDPirates: vsum, vadd, vifelse
import ReverseDiffExpressionsBase: adj, ∂mul, ∂getindex

# Consider tuple case: out = (a1, a2, a3); how to properly record which has been initialized?
# Defined as an alias rather than wrapper.
const BiMap = Dict{Symbol,Set{Symbol}}

function addaliases!(bm::BiMap, s1::Symbol, s2::Symbol)
    push!(get!(() -> Set{Symbol}(), bm, s1), s2)
    push!(get!(() -> Set{Symbol}(), bm, s2), s1)
    bm
end
# Base.in(s::Symbol, bm::BiMap) = s ∈ bm.d
# Base.getindex(bm::BiMap, s::Symbol) = bm.d[s]


include("adjoints.jl")
include("misc_functions.jl")
include("special_diff_rules.jl")
include("reverse_autodiff_passes.jl")

@def_stackpointer_fallback emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
function __init__()
    @add_stackpointer_method emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
end

end # module
