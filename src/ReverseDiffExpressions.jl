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
import ReverseDiffExpressionsBase: ∂mul, ∂getindex

include("adjoints.jl")
include("misc_functions.jl")
include("special_diff_rules.jl")
include("reverse_autodiff_passes.jl")

end # module
