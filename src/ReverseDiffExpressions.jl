module ReverseDiffExpressions

using VectorizationBase, StackPointers, SIMDPirates, DiffRules, LinearAlgebra, PaddedMatrices, StructuredMatrices, ProbabilityDistributions

using PaddedMatrices:
    AbstractFixedSizeVector, AbstractMutableFixedSizeVector, UninitializedVector,
    AbstractFixedSizeMatrix, AbstractMutableFixedSizeMatrix, UninitializedMatrix,
    AbstractFixedSizeArray, AbstractMutableFixedSizeArray, UninitializedArray

using StructuredMatrices: AbstractLowerTriangularMatrix
using ProbabilityDistributions: distribution_diff_rule!

using FunctionWrappers: FunctionWrapper
using MacroTools: postwalk, prewalk, @capture, @q

# import SIMDPirates: vsum, vadd, vifelse
import ReverseDiffExpressionsBase: adj, ∂mul, ∂getindex, RESERVED_INCREMENT_SEED_RESERVED!,
    InitializedVarTracker, add_aliases!, allocate!, initialize!, isallocated, deallocate!



include("adjoints.jl")
include("misc_functions.jl")
include("special_diff_rules.jl")
include("reverse_autodiff_passes.jl")
include("precompile.jl")
_precompile_()

@def_stackpointer_fallback emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
function __init__()
    @add_stackpointer_method emax_dose_response ITPExpectedValue ∂ITPExpectedValue HierarchicalCentering ∂HierarchicalCentering
    _precompile_()
end

end # module
