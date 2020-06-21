
# Should LoopVectorization.lower and ReverseDiffExpressions.lower be distinct?
#import LoopVectorization: lower, lower!
# Because they mean the same thing -- turn obj into Expr -- I'm importing LoopVectorization.lower for now.

# Algorithm for lowering:
# 1. Pick an unpicked func.
# 2. Check if all vars are initialized. If so, go to step 4.
# 3. For all that are not, check if they have a parentfunc. Error if not, if so go to step 1 (picking that parentfunc); when done, resume here.
# 4. Lower func, initializing any vars it defines.
# 5. Return up callstack to 3, or iterate to next unpicked function.
#
# Eventually, this should be improved by picking the order more intelligently.

lower(m::Model) = lower!(Expr(:block), m)
function lower!(q::Expr, m::Model)
    @unpack vars, targets = m
    reset_funclowered!(m)
    reset_varinitialized!(m)
    foreach(t -> lower!(q, m, vars[t]), Iterators.reverse(m.targets))
    push!(q.args, Symbol("##TARGET##"))
    q
end

function asexpr(instr::LoopVectorization.Instruction)
    if instr.mod === Symbol("")
        instr.instr
    else
        Expr(:(.), instr.mod, QuoteNode(instr.instr))
    end
end

function getprop_call!(q::Expr, m::Model, func::Func, retvar::Variable)
    @unpack vars = m
    vparents = parents(func)
    call = Expr(:(.), name(vars[vparents[1]]), QuoteNode(vars[vparents[2]].ref))
    lowernum = num_lowered(retvar)
    retname = return_name(retvar, lowernum)
    if iszero(lowernum)
        push!(q.args, Expr(:(=), retname, call))
    else
        retnametemp = gensym(retname)
        push!(q.args, Expr(:(=), retnametemp, call))
        push!(q.args, Expr(:(=), retname, Expr(:call, :(ReverseDiffExpressions.vadd!), return_name(retvar, lowernum - 1), retnametemp)))
    end
    func.lowered[] = true
    retvar.lowered_count += 1
    nothing
end
function indfunc_call!(q::Expr, m::Model, func::Func, retvar::Variable, check_paireddeps::Bool = true)
    @unpack vars, funcs = m
    vparents = parents(func)
    call = Expr(:call, asexpr(func.instr))
    for vpid ∈ parents(func)
        p = vars[vpid]
        isinitialized(p) || lower!(q, m, p, check_paireddeps)
        push!(call.args, p)
    end
    # indfuncs may get called repeatedly as a result of trying to lower others,
    # due to the immediate lowering performed by constrain_pullbacks
    # so once parents are lowered, we may find that this func has
    # been lowered in that process.
    # Therefore, check and return if so.
    if islowered(func)
        # however, this means some paired deps were skipped
        lower_paired_deps!(q, m, retvar)#vars[first(parents(func))])
        return
    end
    lowernum = num_lowered(retvar)
    retname = return_name(retvar, lowernum)
    if iszero(lowernum)
        push!(q.args, Expr(:(=), retname, call))
    else
        retnametemp = gensym(retname)
        push!(q.args, Expr(:(=), retnametemp, call))
        push!(q.args, Expr(:(=), retname, Expr(:call, :(ReverseDiffExpressions.vadd!), return_name(retvar, lowernum - 1), retnametemp)))
    end
    func.lowered[] = true
    retvar.lowered_count += 1
    nothing
end
function lower_paired_deps!(q::Expr, m::Model, v::Variable)
    for pv ∈ v.paireddeps
        lower!(q, m, m.vars[pv])
    end
end
function lower!(q::Expr, m::Model, v::Variable, check_paireddeps::Bool = true)
    isinitialized(v) && return
    @unpack vars, funcs = m
    # @assert name(v) !== Symbol("L##BAR##")
    vparents = parents(v)
    # check if any constrained
    if iszero(num_lowered(v))
        constrainid = findfirst(pf -> isconstrainttransform(funcs[pf]), vparents)
        skipid = if isnothing(constrainid)
            notupdateingid = findfirst(vparents) do pf
                func = nonindex_parent(m, funcs[pf])
                !func.probdistapi && notupdating(func)
            end
            something(notupdateingid, 1)
        else
            constrainid
        end
        skippf = vparents[skipid]
        lower!(q, m, funcs[skippf], v)
    end
    length(vparents) > 1 && foreach(pf -> lower!(q, m, funcs[pf], v), vparents)
    if check_paireddeps
        lower_paired_deps!(q, m, v)
    end
    # for pf ∈ v.useids
    #     func = funcs[pf]
    #     isindexfunc(func) && lower!(q, m, vars[func.output[]])
    # end
    nothing
end
function return_name(retvar::Variable, lowernum::Int = num_lowered(retvar))
    lowernum + 1 == length(parents(retvar)) ? name(retvar) : Symbol(name(retvar), '#', lowernum, '#')
end
function probdist_call(m::Model, func::Func, retvar::Variable)
    funcupdating = m.gradmodel
    f = funcupdating ? :∂logdensity! : :logdensity
    @unpack vars, funcs = m
    dist = Expr(:call, Expr(:curly, func.instr.instr, Expr(:curly, :Tuple, map(id -> istracked(vars[id]), parents(func))...)))
    call = Expr(:call, Expr(:(.), :ReverseDiffExpressions, QuoteNode(:stack_pointer_call)), f, STACK_POINTER_NAME)
    push!(call.args, dist)
    call
end

function add_probdist_partials!(q::Expr, call::Expr, m::Model, func::Func, retvar::Variable)
    @unpack vars, funcs = m
    ∂tup = Expr(:tuple)
    insert!(call.args, 4, ∂tup)
    for id ∈ parents(func)
        pvar = vars[id]
        if !istracked(pvar)
            push!(∂tup.args, nothing)
            continue
        end
        ∂pvar = getvar!(m, diffsym(pvar))
        lowernum = num_lowered(∂pvar)
        # It isn't fully initialized, but perhaps it isn't partially initialized either.
        if iszero(lowernum)
            # If it hasn't been initialized, we look if one of them is simply missing
            # a needed getindex call to actually extract it.
            found = false
            for pfuncid ∈ parents(∂pvar)
                immediate_parent_func = funcs[pfuncid]
                pfunc = nonindex_parent(m, immediate_parent_func)
                if islowered(pfunc) # the actual parent has been lowered: (∂pvar,) = pfunc(...)
                    found = true
                    # so we extract it: ∂pvar = (∂pvar,)[1]
                    lower!(q, m, immediate_parent_func, ∂pvar)
                    break
                end
            end
            if found
                push!(∂tup.args, return_name(∂pvar, 0))
            else
                push!(∂tup.args, nothing)
            end
        else
            push!(∂tup.args, return_name(∂pvar, lowernum - 1))
        end
    end    
end
function lower!(q::Expr, m::Model, func::Func, retvar::Variable, check_paireddeps::Bool = true)
    func.lowered[] && return
    iszero(func.loopsetid) || return lower_loopset!(q, func, m)
    @unpack vars, funcs = m
    if func.probdistapi
        funcupdating = m.gradmodel
        call = probdist_call(m, func, retvar)
    elseif func.instr === Instruction(:Base, :getproperty)
        return getprop_call!(q, m, func, retvar)
    elseif isindexfunc(func)
        return indfunc_call!(q, m, func, retvar, check_paireddeps)
    else
        lowernum = num_lowered(retvar)
        funcupdating = !(iszero(lowernum) || notupdating(func))
        instr = funcupdating ? ReverseDiffExpressionsBase.MAKEUPDATING[func] : func.instr
        if instr === Instruction(Symbol(""),:constrain_reverse!)
            lower_paired_deps!(q, m, vars[first(parents(func))])
        end
        call = Expr(:call, Expr(:(.), :ReverseDiffExpressions, QuoteNode(:stack_pointer_call)), asexpr(instr), STACK_POINTER_NAME)
        funcupdating && push!(call.args, return_name(retvar, lowernum - 1))
    end
    for vpid ∈ parents(func)
        p = vars[vpid]
        lower!(q, m, p)
        push!(call.args, p)
    end
    if func.probdistapi && funcupdating
        add_probdist_partials!(q, call, m, func, retvar)
    end
    
    retvarid = func.output[]
    ret = Expr(:tuple, STACK_POINTER_NAME)
    call = Expr(:(=), ret, call)
    push!(q.args, call)
    if retvarid ≥ 0
        lowernum = num_lowered(retvar)
        retname = return_name(retvar, lowernum)
        if iszero(lowernum) | funcupdating
            push!(ret.args, retname)
        else
            retnametemp = gensym(retname)
            push!(ret.args, retnametemp)
            push!(q.args, Expr(:(=), retname, Expr(:call, :(ReverseDiffExpressions.vadd!), return_name(retvar, lowernum - 1), retnametemp)))
        end
    end
    func.lowered[] = true
    retvar.lowered_count += 1
    if func.instr.instr === :constrain_pullback!
        let fid1 = retvar.useids[2]
            let fid2 = (vars[funcs[fid1].output[]]).useids[2]
                func2 = funcs[fid2]
                varout = vars[func2.output[]]
                lower!(q, m, func2, varout, false)
                lower_paired_deps!(q, m, varout)
            end
        end
        # @assert false
    end
    nothing
end


function lower_loopset!(q::Expr, func::Func, m::Model)
    push!(q.args, setup_call(m.loops[func.loopsetid]))
end

