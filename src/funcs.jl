
struct Func
    funcid::Int
    instr::Instruction
    output::Vector{Int} # Should support unpacking of returned objecs, whether homogonous arrays or heterogenous tuples.
    vparents::Vector{Int} # should these be Vector{vparent}, or Ints to ids ?
    unconstrainapi::Bool
    probdistapi::Bool
    loopsetid::Int#index into Model's ::Vector{LoopSet}; 0 indicates no ls
    function Func(funcid::Int, instr::Instruction, unconstrainapi::Bool, probdistapi::Bool, loopsetid::Int = 0)
        new(funcid, instr, Int[], Int[], unconstrainapi, probdistapi, loopsetid)
    end
end
# function Func() 
# end

function uses!(f::Func, v::Variable)
    push!(v.useids, f.funcid)
    push!(f.vparents, v.varid)
    nothing
end
function returns!(f::Func, v::Variable)
    push!(f.output, v.varid)
    v.parentfunc = f.funcid
    nothing
end

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

stackpointercall_expr(mod) = Expr(:(.), Expr(:(.), mod, QuoteNode(:ReverseDiffExpressions)), QuoteNote(:stack_pointer_call))


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

