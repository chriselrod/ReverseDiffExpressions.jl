
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
        # drv.vars[i] = getvar!(∂m, moldvars[vparents[i + nparents + 1]])
        drv.vars[i] = getvar!(∂m, moldvars[vparents[i + nparents + 1]])
    end
    drv.vars[0] = var0 = getvar!(∂m.m, diffsym(moldvars[func.output[]]))
    drv
end

function add_section!(∂m::∂Model, drv::DiffRuleVariable, sectionid::Int)
    @unpack vars, funcold, diffrule = drv
    @unpack sections, returns, instructions, dependencies = diffrule
    section = sections[sectionid]
    if isone(sectionid)
        ret = returns[1]
    else
        str = ReverseDiffExpressionsBase.section_two_returns(diffrule)
        if sectionid == 2
            str || return
            ret = returns[2]
        else
            if (vars[sectionid - num_parents(diffrule) - 3]).tracked
                ret = returns[sectionid + str - 1]
            else
                # @show vars[sectionid - num_parents(diffrule) - 3]
                return
            end
        end
    end
    for i ∈ section
        func = Func(instructions[i], false)
        # (instructions[i].instr === :constrain_pullback!) && uses!(func, ∂m.gradvar)
        for j ∈ dependencies[i]
            uses!(func, vars[j])
        end
        vars[i] = if i == ret && sectionid != 2
            if isone(sectionid)
                retv = getvar!(∂m, ∂m.mold.vars[funcold.output[]])
            else
                parent = vars[sectionid - num_parents(diffrule) - 1]
                retv = getvar!(∂m.m, diffsym(name(parent)))
            end
        else
            retv = getvar!(∂m.m, gensym(:temp))
        end
        retv.tracked = true
        returns!(func, retv)
        addfunc!(∂m.m, func)
    end
end

function add_fallback_diffrule!(∂m::∂Model, func::Func)
    @unpack m, mold = ∂m
    # add func as var, return DiffRuleVariable
    v = addvarref!(∂m.m, asexpr(func.instr))
    drv = DiffRuleVariable(∂m, ReverseDiffExpressionsBase.FALLBACK_RULES[length(parents(func))], func)
    
    retvsym = gensym(:rrule_LHS)
    rrulefunc = Func(Instruction(:ChainRules,:rrule), false)
    drv.vars[1] = rruleretv = addvar!(∂m.m, retvsym)
    rruleretv.tracked = true
    returns!(rrulefunc, rruleretv)
    uses!(rrulefunc, v)
    foreach(arg -> uses!(rrulefunc, arg), @view(drv.vars[begin:-1]))
    addfunc!(m, rrulefunc)
    funcfirst = Func(Instruction(:Base,:first), false)
    uses!(funcfirst, rruleretv)
    drv.vars[2] = retvar = getvar!(∂m, mold.vars[func.output[]])
    returns!(funcfirst, retvar)
    retvar.tracked = true
    addfunc!(m, funcfirst)
    drv
end
function add_diffrule!(∂m::∂Model, dr::DiffRule, func::Func)
    drv = DiffRuleVariable(∂m, dr, func)
    add_section!(∂m, drv, 1)
    drv
end


function add_view_diff!(∂m::∂Model, func::Func)
    gi_forward = Func(func.instr, false)
    gi_reverse = Func(func.instr, false)
    vparents = parents(func)
    moldvars = ∂m.mold.vars
    p = moldvars[first(vparents)]
    inputvf = getvar!(∂m, p); inputvf.tracked = true
    inputvr = getvar!(∂m.m, diffsym(name(p))); inputvr.tracked = true
    uses!(gi_forward, inputvf)
    uses!(gi_reverse, inputvr)
    for i ∈ @view(vparents[2:end])
        indold = moldvars[i]
        if isref(indold)
            ind = addvar!(∂m.m, Symbol(""))
            ind.ref = indold.ref
        else
            ind = addvar!(∂m.m, name(indold))
        end
        uses!(gi_forward, ind)
        uses!(gi_reverse, ind)
    end
    retv = moldvars[func.output[]]
    retvf = getvar!(∂m, retv); retvf.tracked = true
    returns!(gi_forward, retvf)
    retvr = getvar!(∂m.m, diffsym(name(retv))); retvr.tracked = true
    returns!(gi_reverse, retvr)
    addfunc!(∂m.m, gi_forward)
    addfunc!(∂m.m, gi_reverse)
    nothing
end

function add_probdist_diff!(∂m::∂Model, func::Func)
    ∂loglik = Func(func.instr, true)
    moldvars = ∂m.mold.vars
    for i ∈ parents(func)
        uses!(∂loglik, getvar!(∂m, moldvars[i]))
    end
    tup = addvar!(∂m.m, gensym(:tup))
    tup.tracked = true
    returns!(∂loglik, tup)
    addfunc!(∂m.m, ∂loglik)
    getconstindex!(∂m.m, ∂m.m.vars[0], tup, 1)
    ∂tup = addvar!(∂m.m, gensym(:∂tup))
    getconstindex!(∂m.m, ∂tup, tup, 2)
    for i ∈ parents(func)
        p = moldvars[i]
        if istracked(p)
            retv = getvar!(∂m.m, diffsym(name(p))); retv.tracked = true
            getconstindex!(∂m.m, retv, ∂tup, i)
        end
    end
end
function add_constrain_diff!(∂m::∂Model, funcold::Func)
    drvc = DiffRuleVariable(∂m, DERIVATIVERULES[InstructionArgs(Instruction(:DistributionParameters,:constrain),3)], funcold)
    constrain_pullback = Func(Instruction(:constrain_pullback!), false)
    uses!(constrain_pullback, ∂m.gradvar)
    for i ∈ -3:-1
        uses!(constrain_pullback, drvc.vars[i])
    end
    tempv = getvar!(∂m.m, gensym(:constrainpullbacktup)); tempv.tracked = true
    returns!(constrain_pullback, tempv)
    addfunc!(∂m.m, constrain_pullback)
    retv = getvar!(∂m, ∂m.mold.vars[funcold.output[]]); retv.tracked = true
    getconstindex!(∂m.m, retv, tempv, 1)
    ∂retv = getvar!(∂m.m, diffsym(name(retv))); ∂retv.tracked = true
    getconstindex!(∂m.m, ∂retv, tempv, 2)
    
    constrain_reverse = Func(Instruction(:constrain_reverse!), false)
    uses!(constrain_reverse, ∂retv)
    uses!(constrain_reverse, drvc.vars[-1])
    nothing
end
function add_no_diff!(∂m::∂Model, funcold::Func)
    func = Func(funcold.instr, funcold.probdistapi)
    for i ∈ parents(funcold)
        uses!(func, getvar!(∂m, ∂m.mold.vars[i]))
    end
    returns!(func, getvar!(∂m, ∂m.mold.vars[funcold.output[]]))
    addfunc!(∂m.m, func)
    nothing
end
function has_tracked_parents(∂m::∂Model, func::Func)
    any(i -> istracked(∂m.mold.vars[i]), parents(func))
end

function add_func_diff!(∂m::∂Model, func::Func)
    has_tracked_parents(∂m, func) || return add_no_diff!(∂m, func)
    if func.probdistapi
        return add_probdist_diff!(∂m, func)
    elseif func.instr.instr === :constrain
        return add_constrain_diff!(∂m, func)
    elseif isindexfunc(func)
        if iszero(∂m.mold.vars[func.output[]].varid)
            return add_no_diff!(∂m, func)
        else
            return add_view_diff!(∂m, func)
        end
    end
    instrargs = InstructionArgs(func)
    dr = get(DERIVATIVERULES, instrargs, nothing)
    drv = isnothing(dr) ? add_fallback_diffrule!(∂m, func) : add_diffrule!(∂m, dr, func)
    for i ∈ 2:length(drv.diffrule.sections)
        add_section!(∂m, drv, i)
    end
end





