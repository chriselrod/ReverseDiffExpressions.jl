
struct Model
    vars::Vector{Variable}
    funcs::Vector{Func}
    loops::Vector{LoopSet}
    tracker::Dict{Symbol,Int}
    mod::Module
    modsym::Symbol
    funcdict::Dict{Func,Int}
    inputvars::Vector{Int}
    varid::Ref{UInt}
    # targetinit::RefValue{Bool}
    function Model(mod::Module = ReverseDiffExpressions)
        target = Variable(Symbol("##TARGET##"), 0, true)
        ein = Variable(Symbol("##ONE##"), 1, true)
        new(Variable[ein, target], Func[], LoopSet[], Dict{Symbol,Int}(), mod, Symbol(mod), Dict{Func,Int}(), Int[], Ref(UInt(2)))
    end
end


reset_funclowered!(m::Model) = foreach(f -> (f.lowered[] = false), m.funcs)
reset_varinitialized!(m::Model) = foreach(v -> (v.initialized = isref(v)), m.vars)
onevar(m::Model) = @inbounds m.vars[1]
targetvar(m::Model) = @inbounds m.vars[2]

function addvar!(m::Model, s::Symbol)
    @unpack vars, tracker = m
    v = Variable(s)
    push!(vars, v)
    tracker[s] = v.varid = length(vars)
    v
end

function getvar!(m::Model, s::Symbol)
    @unpack vars, tracker = m
    id = get(tracker, s, nothing)
    id === nothing ? addvar!(m, s) : vars[id]
end
function Func(m::Model, instr::Symbol, args...)
    ins = Instruction(instr)
    ins = ins ∈ keys(LoopVectorization.COST) ? ins : Instruction(m.modsym, instr)
    Func(ins, args...)
end

function addfunc!(m::Model, f::Func)
    fid = get!(m.funcdict, f) do
        push!(m.funcs, f)
        fid = length(m.funcs)
        for p ∈ f.vparents
            push!(m.vars[p].useids, fid)
        end
        fid
    end
    ret = m.vars[m.funcs[fid].output[]]
    ret.parentfunc = fid
    ret
end


uses!(func::Func, m::Model, x::Symbol) = uses!(func, getvar!(m, x))
# function uses!(f::Func, m::Model, x)
#     @unpack otherargs, vparents = f
#     push!(otherargs, x)
#     push!(vparents, -length(otherargs))
#     nothing
# end

