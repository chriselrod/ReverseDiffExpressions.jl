module ReverseDiffExpressions

using PaddedMatrices, StackPointers, DiffRules

using ProbabilityDistributions: distribution_diff_rule!

using FunctionWrappers: FunctionWrapper
using MacroTools: postwalk, prewalk, @capture, @q

import SIMDPirates: vsum, vadd, vifelse

include("adjoints.jl")
include("misc_functions.jl")
include("special_diff_rules.jl")
include("reverse_autodiff_passes.jl")

end # module
