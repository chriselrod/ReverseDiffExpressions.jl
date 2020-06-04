
struct DiffRuleVariable
    diffrule::DiffRule
    vars::OffsetVector{Variable,Vector{Variable}}
    funcold::Func
end
function DiffRuleVariable(∂m::∂Model, dr::DiffRule, func::Func)
    nparents = num_parents(dr)
    vars = OffsetVector{Variable}(undef, -nparents:last(last(dr.sections)))
    drv = DiffRuleVariable( dr, vars, func )
    vparents = parents(func)
    moldvars = ∂m.mold.vars
    for i ∈ -nparents:-1
        drv.vars[i] = getvar!(∂m, moldvars[vparents[i + nparents + 1]])
    end
    drv.vars[0] = var0 = getvar!(∂m.m, diffsym(name(moldvars[func.output[]])))
    if func.instr === Instruction(:DistributionParameters, :constrain)
        @assert nparents == 3
        alloc_adj_instr = Func(Instruction(:DistributionParameters, :alloc_adj), false, false)
        uses!(alloc_adj_instr, ∂m.gradvar)
        for i ∈ 1-nparents:-1
            uses!(alloc_adj_instr, drv.vars[i])
        end
        returns!(alloc_adj_instr, var0)
    end
    drv
end

function add_section!(∂m::∂Model, drv::DiffRuleVariable, sectionid::Int)
    @unpack vars, funcold, diffrule = drv
    @unpack sections, returns, instructions, dependencies = diffrule
    section = sections[sectionid]
    if isone(sectionid)
        ret = returns[1]
    else
        parent = vars[sectionid - num_parents(diffrule) - 1]
        str = ReverseDiffExpressionsBase.section_two_returns(diffrule)
        if sectionid == 2
            str || return
            ret = returns[2]
        elseif parent.tracked
            ret = returns[sectionid + str - 1]
        else
            return
        end
    end
    for i ∈ section
        func = Func(instructions[i], false, false)
        for j ∈ dependencies[i]
            # @show diffrule j
            uses!(func, vars[j])
        end
        vars[i] = if isone(sectionid)
            returns!(func, getvar!(∂m, ∂m.mold.vars[funcold.output[]]))
        elseif sectionid != 2 && i == ret
            parent = vars[sectionid - num_parents(diffrule) - 1]
            returns!(func, getvar!(∂m.m, diffsym(name(parent))))
        else
            returns!(func, getvar!(∂m.m, gensym(:temp)))
        end
    end
end

function add_fallback_diffrule!(∂m::∂Model, func::Func)
    @unpack m, mold = ∂m
    # add func as var, return DiffRuleVariable
    v = addvarref!(∂m.m, asexpr(func.instr))
    
    drv = DiffRuleVariable(∂m, ReverseDiffExpressionsBase.FALLBACK_RULES[length(parents(func))], func)
    
    retvsym = gensym(:rrule_LHS)
    rrulefunc = Func(Instruction(:ChainRules,:rrule), false, false)
    rruleretv = addvar!(∂m.m, retvsym)
    returns!(rrulefunc, rruleretv)
    uses!(rrulefunc, v)
    foreach(arg -> uses!(rrulefunc, arg), @view(drv.vars[begin:-1]))
    addfunc!(m, rrulefunc)
    funcfirst = Func(Instruction(:Base,:first), false, false)
    uses!(funcfirst, rruleretv)
    drv.vars[1] = retvar = getvar!(∂m, mold.vars[func.output[]])
    returns!(funcfirst, retvar)
    addfunc!(m, funcfirst)
    drv
end
function add_diffrule!(∂m::∂Model, dr::DiffRule, func::Func)
    drv = DiffRuleVariable(∂m, dr, func)
    add_section!(∂m, drv, 1)
    drv
end

function add_func_diff!(∂m::∂Model, func::Func)
    if func.instr.instr === :view || func.instr.instr === :getindex || func.instr.instr ∈ [:first, :second, :third, :fourth, :fifth, :sixth, :seventh, :eigth, :ninth, :last]
        return add_view_diff!(∂m::∂Model, func::Func)
    end
    instrargs = InstructionArgs(func)
    dr = get(DERIVATIVERULES, instrargs, nothing)
    drv = isnothing(dr) ? add_fallback_diffrule!(∂m, func) : add_diffrule!(∂m, dr, func)
    for i ∈ 2:length(drv.diffrule.sections)
        add_section!(∂m, drv, i)
    end
end





