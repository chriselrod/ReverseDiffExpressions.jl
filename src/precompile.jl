function _precompile_()
    ccall(:jl_generating_output, Cint, ()) == 1 || return nothing
    precompile(Tuple{typeof(Base.unsafe_convert),Type{Ref{typeof(ReverseDiffExpressions.diagonal_diff_rule!)}},Base.RefValue{typeof(ReverseDiffExpressions.diagonal_diff_rule!)}})
    precompile(Tuple{typeof(Base.unsafe_convert),Type{Ref{typeof(ReverseDiffExpressions.getindex_diff_rule!)}},Base.RefValue{typeof(ReverseDiffExpressions.getindex_diff_rule!)}})
    precompile(Tuple{typeof(Base.unsafe_convert),Type{Ref{typeof(ReverseDiffExpressions.mul_diff_rule!)}},Base.RefValue{typeof(ReverseDiffExpressions.mul_diff_rule!)}})
end
