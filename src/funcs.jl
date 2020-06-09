using Base: RefValue
using LoopVectorization: parents, name, parent

struct Func
    instr::Instruction
    output::RefValue{Int} # Should support unpacking of returned objecs, whether homogonous arrays or heterogenous tuples.
    vparents::Vector{Int} # should these be Vector{vparent}, or Vector{Int} of ids ?
    loopsetid::Int#index into Model's ::Vector{LoopSet}; 0 indicates no ls
    probdistapi::Bool
    lowered::RefValue{Bool}
end
function Func(instr::Instruction, probdistapi::Bool = false, loopsetid::Int = 0)
    Func(instr, Ref{Int}(), Int[], loopsetid, probdistapi, Ref(false))
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
    push!(parents(f), v.varid)
    v
end
function returns!(f::Func, v::Variable)
    @assert name(v) != Symbol("##TARGET####BAR##")
    f.output[] = v.varid
    # push!(parents(v), f)
    v.initialized = false
    v
end
lowered(f::Func) = f.lowered[]
LoopVectorization.parents(f::Func) = f.vparents
LoopVectorization.instruction(f::Func) = f.instr
ReverseDiffExpressionsBase.InstructionArgs(f::Func) = InstructionArgs(instruction(f), length(parents(f)))

stackpointercall_expr(mod) = Expr(:(.), Expr(:(.), mod, QuoteNode(:ReverseDiffExpressions)), QuoteNote(:stack_pointer_call))

function isindexfunc(func::Func)
    func.instr.instr === :view || func.instr.instr === :getindex || func.instr.instr ∈ (:first, :second, :third, :fourth, :fifth, :sixth, :seventh, :eigth, :ninth, :last)
end

# function getconstindex!(m::Model, index::Integer, vin::Variable)
# end

