function LoopVectorization.lower(m::Model, fun::Func, mod)
    if fun.probdistapi
        lower_probdistfun(m, fun, mod)
    elseif fun.unconstrainapi
        lower_unconstrain(m, fun, mod)
    elseif iszero(fun.loopsetid)
        lower_normalfun(m, fun, mod)
    else
        lower_loopset(m, fun, mod)
    end
end


function lower_normalfun(m::Model, fun::Func, mod)
    @unpack instr, output, vparents = fun
    spc = stackpointercall_expr(mod)
    call = Expr(:call, spc, Expr(:(.), mod, QuoteNode(f)), STACK_POINTER_NAME)
    foreach(p -> push!(call.args, name(p)), vparents)
    # if diff
        # for p ∈ vparents
            # push!(call.args, Expr(:call, Expr(:curly, 
            # istracked(p) && push!(
        # end
        # foreach(p -> push!(call.args, name(p)), vparents)
    # end
    Expr(:(=), name(output), call)
end

