using Base: RefValue
using LoopVectorization: parents, name, parent

struct Func
    instr::Instruction
    output::RefValue{Int} # Should support unpacking of returned objecs, whether homogonous arrays or heterogenous tuples.
    vparents::Vector{Int} # should these be Vector{vparent}, or Ints to ids ?
    loopsetid::Int#index into Model's ::Vector{LoopSet}; 0 indicates no ls
    lowered::RefValue{Bool}
end
function Func(instr::Instruction, unconstrainapi::Bool, probdistapi::Bool, loopsetid::Int = 0)
    Func(instr, Ref(0), Int[], loopsetid, Ref(false))
end

function Base.hash(f::Func, u::UInt)
    @unpack instr, vparents = f
    u = hash(instr, u)
    for p ∈ vparents
        u = hash(p, u)
    end
    u
end
Base.isequal(f1::Func, f2::Func) = f1.instr == f2.instr && f1.vparents == f2.vparents

function uses!(f::Func, v::Variable)
    # push!(v.useids, f.funcid)
    push!(f.vparents, v.varid)
    v
end
function returns!(f::Func, v::Variable)
    f.output[] = v.varid
    v.initialized = false
    nothing
end
lowered(f::Func) = f.lowered[]
LoopVectorization.parents(f::Func) = f.vparents


stackpointercall_expr(mod) = Expr(:(.), Expr(:(.), mod, QuoteNode(:ReverseDiffExpressions)), QuoteNote(:stack_pointer_call))


