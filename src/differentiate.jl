
diffsym(s::Symbol) = Symbol(s, "##BAR##")
diffsym(v::Variable) = diffsym(name(v))

function differentiate(m::Model)
    differentiate!(∂Model(m))
end

function differentiate!(∂m::∂Model)
    @unpack mold = ∂m
    reset_varinitialized!(mold)
    reset_funclowered!(mold)
    
    # diffvars = Vector{DiffRuleVariable}(undef, length(mold.funcs))
    for (n,func) ∈ enumerate(mold.funcs) # is 
        lowered(func) || add_func_diff!(∂m, func)
    end
    ∂m.m
end

