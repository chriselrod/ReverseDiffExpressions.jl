
mutable struct Func
    instr::Instruction
    output::Variable
    vparents::Vector{Variable}
    probdistapi::Bool
    lsid::Int#index into Model's ::Vector{LoopSet}; 0 indicates no ls
    function Func()
        new()
    end
end
# function Func() 
# end

function LoopVectorization.lower(fun::Func, mod)
    if fun.probdistapi
        lower_probdistfun(fun, mod)
    elseif fun.loopset
        lower_loopset(fun, mod)
    else
        lower_normalfun(fun, mod)
    end
end

spc_expr(mod) = Expr(:(.), Expr(:(.), mod, QuoteNode(:ReverseDiffExpressions)), QuoteNote(:stack_pointer_call))

function lower_normalfun(fun::Func, mod)
    @unpack instr, output, vparents = fun
    spc = spc_expr(mod)
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

