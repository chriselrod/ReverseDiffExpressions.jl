
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
    q = Expr(:block)
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

function lower!(q::Expr, func::Func, m::Model)
    iszero(func.loopsetid) || return lower_loopset!(q, func, m)
    @unpack vars, funcs = m

    call = Expr(:call, Expr(:(.), :ReverseDiffExpressions, QuoteNode(:stack_pointer_call)), convert(Expr, func.instr), STACK_POINTER_NAME)
    for vpid ∈ parents(func)
        p = vars[vpid]
        p.initialized || lower!(q, funcs[p.parentfunc], m)
        push!(call.args, p)
    end
    retvarid = func.output[]
    ret = Expr(:tuple, STACK_POINTER_NAME)
    call = Expr(:(=), ret, call)
    push!(q.args, call)
    if !iszero(retvarid)
        retvar = vars[retvarid]
        if retvarid == 2
            retvname = gensym("target")
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

