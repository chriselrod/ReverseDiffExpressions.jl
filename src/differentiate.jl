
function differentiate(m::Model)
    differentiate!(Model(m.mod), m)
end

function differentiate!(∂m::Model, m::Model)
    Nfuncs = length(m.funcs)
    diffvars = Vector{OffsetVector{Variable}}(undef, Nfuncs) # store vars in DiffRuleOperation order
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
        lowered(func) || add_forward_pass_func!(∂m, diffvars, func, m)
    end
    reset_funclowered!(m)
    q
end

function add_forward_pass_func!(∂m::Model, diffvars::Vector{Vector{Variable}}, func::Func, m::Model)
    # Need to implement differentiate_loopset; most of the work should be completed in src/loopsets.
    iszero(func.loopsetid) || return differentiate_loopset!(q, func, m)

    for vpid ∈ parents(func)
        p = vars[vpid]
        p.initialized || # add p
    end
    retvarid = func.output[]
    if revarid != 0 && retvarid != 2
        # p.initalized = true
    end
    func.lowered[] = true
end

