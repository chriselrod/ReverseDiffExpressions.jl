using ReverseDiffExpressions, LoopVectorization
using ReverseDiffExpressions.LoopSetDerivatives
using Test

@testset "ReverseDiffExpressions.jl" begin

    AmulBq = :(for m ∈ 1:M, n ∈ 1:N
                C[m,n] = zero(eltype(B))
                for k ∈ 1:K
                C[m,n] += A[m,k] * B[k,n]
                end
                end);

    lsAmulB = LoopVectorization.LoopSet(AmulBq);

    tracked_vars = Set([:A, :B]);
    ∂lsAmulB = ReverseDiffExpressions.LoopSetDerivatives.∂LoopSet(lsAmulB, tracked_vars);
    ∂lsAmulB.fls
    ∂lsAmulB.rls
    # Write your own tests here.
end
