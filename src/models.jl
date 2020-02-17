
struct Model
    vars::Vector{Variable}
    funcs::Vector{Func}
    loops::Vector{LoopSet}
    tracker::Dict{Symbol,Int}
    mod::Symbol
    function Model(mod = :ReverseDiffExpressions)
        ein = Variable(Symbol("##ONE##"), 1, true)
        target = Variable(Symbol("##TARGET##"), 2, true)
        Model(Variable[ein, target], Func[], LoopSet[], Dict{Symbol,Int}(), mod)
    end    
end


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

addfunc!(m::Model, instr::Symbol, args...) = addfunc!(m, Instruction(m.mod, :instr), args...)
function addfunc!(m::Model, instr::Instruction, unconstrainapi::Bool, probdistapi::Bool, loopsetid::Int = 0)
    @unpack funcs = m
    f = Func(length(funcs) + 1, instr, unconstrainapi, probdistapi, loopsetid)
    push!(funcs, f)
end



