
# Should LoopVectorization.lower and ReverseDiffExpressions.lower be distinct?
import LoopVectorization: lower, lower!
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
    reset_funclowered!(m)
    reset_varinitialized!(m)
    Nfuncs = length(m.funcs)
    # target = targetvar(m)
    # if iszero(length(target.useids))
        # lower!(q, target, m)
    for n ∈ 0:Nfuncs-1
        # Because it recursively calls to lower funcs on which it is dependendent,
        # trying to lower the last first (which probably depend on many previous ones)
        # should lower in a cache-friendly order, i.e. things will be defined in the
        # resulting expression closer to when they are used.
        # I'm sure much smarter algorithms exist.
        func = m.funcs[Nfuncs - n]
        lowered(func) || lower!(q, func, m)
    end
    q
end

function asexpr(instr::LoopVectorization.Instruction)
    if instr.mod === Symbol("")
        instr.instr
    else
        Expr(:(.), instr.mod, QuoteNode(instr.instr))
    end
end

function getprop_call!(q::Expr, func::Func, m::Model)
    @unpack vars = m
    vparents = parents(func)
    gp = Expr(:(.), name(vars[vparents[1]]), QuoteNode(vars[vparents[2]].ref))
    retvar = vars[func.output[]]
    retvar.initialized = true
    line = Expr(:(=), name(retvar), gp)
    push!(q.args, line)
    func.lowered[] = true
end
function indfunc_call!(q::Expr, func::Func, m::Model)
    @unpack vars, funcs = m
    vparents = parents(func)
    call = Expr(:call, asexpr(func.instr))
    for vpid ∈ parents(func)
        p = vars[vpid]
        p.initialized || foreach(pf -> lower!(q, funcs[pf], m), parents(p))
        push!(call.args, p)
    end
    retvarid = func.output[]
    if retvarid ≥ 0
        retvar = vars[retvarid]
        retvname = iszero(retvarid) ? gensym(:target) : name(retvar)
        call = Expr(:(=), retvname, call)
        push!(q.args, call)
        if iszero(retvarid)
            push!(q.args, Expr(:(+=), name(retvar), retvname))
        else
            retvar.initialized = true
        end
    else
        push!(q.args, call)
    end
    func.lowered[] = true
end

function lower!(q::Expr, func::Func, m::Model)
    iszero(func.loopsetid) || return lower_loopset!(q, func, m)
    @unpack vars, funcs = m
    if func.probdistapi
        f = m.gradmodel ? :∂logdensity! : :logdensity
        dist = Expr(:call, Expr(:curly, func.instr.instr, Expr(:curly, :Tuple, map(id -> istracked(m.vars[id]), parents(func))...)))
        call = Expr(:call, Expr(:(.), :ReverseDiffExpressions, QuoteNode(:stack_pointer_call)), f, STACK_POINTER_NAME, dist)
    elseif func.instr === Instruction(:Base, :getproperty)
        return getprop_call!(q, func, m)
    elseif isindexfunc(func)
        return indfunc_call!(q, func, m)
    else
        call = Expr(:call, Expr(:(.), :ReverseDiffExpressions, QuoteNode(:stack_pointer_call)), asexpr(func.instr), STACK_POINTER_NAME)
    end
    for vpid ∈ parents(func)
        p = vars[vpid]
        p.initialized || foreach(pf -> lower!(q, funcs[pf], m), parents(p))
        push!(call.args, p)
    end
    retvarid = func.output[]
    ret = Expr(:tuple, STACK_POINTER_NAME)
    call = Expr(:(=), ret, call)
    push!(q.args, call)
    if retvarid ≥ 0
        retvar = vars[retvarid]
        if iszero(retvarid)
            retvname = gensym(:target)
            push!(ret.args, retvname)
            push!(q.args, Expr(:(+=), name(retvar), retvname))
        else
            push!(ret.args, name(retvar))
            retvar.initialized = true
        end
    end
    func.lowered[] = true
end


function lower_loopset!(q::Expr, func::Func, m::Model)
    push!(q.args, setup_call(m.loops[func.loopsetid]))
end

