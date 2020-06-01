
struct Model
    vars::OffsetVector{Variable,Vector{Variable}}
    funcs::Vector{Func}
    loops::Vector{LoopSet}
    tracker::Dict{Symbol,Int} # maps symbol to varid
    mod::Module
    modsym::Symbol
    funcdict::Dict{Func,Int}
    inputvars::Vector{Int}
    varid::Ref{UInt}
    tracked::Vector{Bool}
    gradmodel::Bool
    # targetinit::RefValue{Bool}
    function Model(mod::Module = ReverseDiffExpressions, gradmodel::Bool = false)
        target = Variable(Symbol("##TARGET##"), 0, true)
        ein = Variable(Symbol("##ONE##"), 1, false)
        new(OffsetVector(Variable[target, ein], -1), Func[], LoopSet[], Dict{Symbol,Int}(), mod, Symbol(mod), Dict{Func,Int}(), Int[], Ref(UInt(2)), Bool[], gradmodel)
    end
end

# struct DiffRuleVarFunc
    # diffrule::DiffRule
    # func::Func
    # variables::OffsetVector{Variable,Vector{Variable}}
# end

struct ∂Model # Houses meta data.
    m::Model
    mold::Model
    mapping::Vector{Int} # maps old vars to new ones
    ∂mapping::Vector{Int} # maps old vars to new ∂ones
end
∂Model(mold::Model) = ∂Model(Model(mold.mod, true), mold, Int[], Int[])

# corresponding_func(∂m::∂Model, func::Func) = ∂m.m.funcs[∂m.mapping[∂m.mold.funcdict[func]]]

reset_funclowered!(m::Model) = foreach(f -> (f.lowered[] = false), m.funcs)
function reset_varinitialized!(m::Model)
    foreach(v -> (v.initialized = isref(v)), m.vars)
    foreach(v -> initialize_var!(m, v), m.inputvars)
end
onevar(m::Model) = @inbounds m.vars[1]
targetvar(m::Model) = @inbounds m.vars[0]

getparent(m::Model, v::Variable, i::Int = 1) = getfunc(m, parents(v)[i])
getfunc(m::Model, i::Integer) = m.funcs[i]
getvar(m::Model, i::Integer) = m.vars[i]
initialize_var!(m::Model, vid::Integer) = getvar(m, vid).initialized = true

function addvar!(m::Model, s::Symbol)::Variable
    addvar!(m, Variable(s, length(m.vars)))
end
function addvar!(m::Model, v::Variable)::Variable
    @unpack vars, tracker = m
    push!(vars, v)
    tracker[v.name] = v.varid
    v
end
function addvarref!(m::Model, ref)::Variable
    @assert !(ref isa Variable)
    @unpack vars, tracker = m
    s = gensym()
    v = Variable(s, length(m.vars))
    push!(vars, v)
    tracker[s] = v.varid
    v.ref = ref
    v
end
getvar!(m::Model, ref)::Variable = addvarref!(m, ref)

function getvar!(m::Model, s::Symbol)::Variable
    @unpack vars, tracker = m
    id = get(tracker, s, nothing)
    isnothing(id) ? addvar!(m, s) : vars[id]
end
getvar!(m::Model, s::Expr)::Variable = addvar!(m, s)

function getvar!(∂m::∂Model, vold::Variable)::Variable
    @unpack m = ∂m
    @unpack vars, tracker = m
    s = name(vold)
    id = get(tracker, s, nothing)
    vnew = if isnothing(id)
        v = addvar!(m, s)
        isref(vold) && (v.ref = vold.ref)
        v
    else
        vars[id]
    end
    vnew.tracked = vold.tracked
    vnew
end

function addvar!(m::Model, s::Expr)::Variable # unpack LHS tuple
    @assert s.head === :tuple
    packedtuple = gensym(:packedtuple)
    pt = addvar!(m, packedtuple)
    for i ∈ eachindex(s.args)
        gi = Func(:getindex)
        v = getvar!(m, s.args[i])
        returns!(gi, v)
        uses!(gi, pt)
        uses!(gi, getvar!(m, i))
        addfunc!(m, gi)
    end
    pt
end

function Func(m::Model, instr::Symbol, args...)
    ins = Instruction(instr)
    ins = ins ∈ keys(LoopVectorization.COST) ? ins : Instruction(m.modsym, instr)
    Func(ins, args...)
end

function addfunc!(m::Model, f::Func)
    # @show m
    fid = get!(m.funcdict, f) do
        push!(m.funcs, f)
        fid = length(m.funcs)
#        @show f (typeof(m.vars), length(m.vars))
        for p ∈ f.vparents
            push!(m.vars[p].useids, fid)
        end
        fid
    end
    ret = m.vars[m.funcs[fid].output[]]
    push!(parents(ret), fid)
    ret
end


uses!(func::Func, m::Model, x::Symbol) = uses!(func, getvar!(m, x))
# function uses!(f::Func, m::Model, x)
#     @unpack otherargs, vparents = f
#     push!(otherargs, x)
#     push!(vparents, -length(otherargs))
#     nothing
# end

