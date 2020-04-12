
function differentiate(m::Model)
    differentiate!(Model(m.mod), m)
end

function differentiate!(∂m::Model, m::Model)
    reset_funclowered!(m)
    reset_varinitialized!(m)
    Nfuncs = length(m.funcs)
    diffvars = Vector{OffsetVector{Variable}}(undef, Nfuncs) # store vars in DiffRuleOperation order
    for n ∈ 1:Nfuncs # is 
        func = m.funcs[n]
        lowered(func) || add_forward_pass_func!(∂m, diffvars, func, m)
    end
    reset_funclowered!(m)
    q
end

function add_forward_pass_func!(∂m::Model, diffvars::Vector{Vector{Variable}}, func::Func, m::Model)
    # Need to implement differentiate_loopset; most of the work should be completed in src/loopsets.
    iszero(func.loopsetid) || return differentiate_loopset!(q, func, m)

    for vpid ∈ parents(func)
        p.initialized || add_forward_pass_func!(∂m, diffvars, getparent(m, getvar(m, vpid)), m)
    end
    retvarid = func.output[]
    if revarid != 0 && retvarid != 2
        # p.initalized = true
    end
    func.lowered[] = true
end

