const NOOPDIFFS = Set{Symbol}( ( :AutoregressiveMatrix, :adjoint ))

function noopdiff!(first_pass, second_pass, tracked_vars, out, f, A, mod)
    track = false
    seedout = Symbol("###seed###", out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track = true
        seeda = Symbol("###seed###", a)
        pushfirst!(second_pass.args, :( $seeda = $mod.RESERVED_INCREMENT_SEED_RESERVED( $seedout, $seeda )))
    end
    track && push!(tracked_vars, out)
    push!(first_pass.args, :($out = $f($(A...))))
    nothing
end

# function reverse_diff_ifelse!(first_pass, second_pass, tracked_vars, cond, conditionaleval, alternateeval)
    # cond_eval_first_pass = quote end; cond_eval_second_pass = quote end
    # reverse_diff_pass!(cond_eval_first_pass, cond_eval_second_pass, conditionaleval, tracked_vars)
    # alt_eval_first_pass = quote end; alt_eval_second_pass = quote end
    # reverse_diff_pass!(alt_eval_first_pass, alt_eval_second_pass, alternateeval, tracked_vars)
    # push!(first_pass.args, quote
        # if $cond
            # $cond_eval_first_pass
        # else
            # $alt_eval_first_pass
        # end
    # end)
    # pushfirst!(second_pass.args, quote
        # if $cond
            # $cond_eval_second_pass
        # else
            # $alt_eval_second_pass
        # end
    # end)
    # nothing
# end

function reverse_diff_pass!(first_pass, second_pass, expr, tracked_vars, mod, verbose = false)
    postwalk(expr) do x
        if @capture(x, out_ = f_(A__))
            differentiate!(first_pass, second_pass, tracked_vars, out, f, A, mod, verbose)
        elseif @capture(x, out_ = A_) && isa(A, Symbol)
            push!(first_pass.args, x)
            pushfirst!(second_pass.args, :( $(Symbol("###seed###", A)) = $mod.RESERVED_INCREMENT_SEED_RESERVED($(Symbol("###seed###", out)), $(Symbol("###seed###", A)) )) )
            A ∈ tracked_vars && push!(tracked_vars, out)
        # elseif @capture(x, if cond_; conditionaleval_; else; alternateeval_ end)
            # reverse_diff_ifelse!(first_pass, second_pass, tracked_vars, cond, conditionaleval, alternateeval)
        # else
        #     push!(first_pass.args, x)
        end
        x
    end
end

function apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, diffrules::NTuple{N}, mod) where {N}
    track_out = false
    push!(first_pass.args, :($out = $f($(A...))))
    seedout = Symbol("###seed###", out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track_out = true
        ∂ = Symbol("###adjoint###_##∂", out, "##∂", a, "##")
        push!(first_pass.args, :($∂ = $(diffrules[i])))
        pushfirst!(second_pass.args, :( $(Symbol("###seed###", a)) = $mod.RESERVED_INCREMENT_SEED_RESERVED($seedout, $∂, $(Symbol("###seed###", a)) )) )
    end
    track_out && push!(tracked_vars, out)
    nothing
end
function apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, diffrule, mod)
    length(A) == 1 || throw("length(A) == $(length(A)); must equal 1 when passed diffrules are: $(diffrule)")
    track_out = false
    push!(first_pass, :($out = $f($(A...))))
    seedout = Symbol("###seed###", out)
    for i ∈ eachindex(A)
        A[i] ∈ tracked_vars || continue
        track_out = true
        ∂ = Symbol("###adjoint###_##∂", out, "##∂", a, "##")
        push!(first_pass.args, :($∂ = $(diffrule)))
        pushfirst!(second_pass.args, :( $(Symbol("###seed###", A[i])) = $mod.RESERVED_INCREMENT_SEED_RESERVED($seedout, $∂, $(Symbol("###seed###", A[i])) )) )
    end
    track_out && push!(tracked_vars, out)
    nothing
end


"""
This function applies reverse mode AD.

"A" lists the arguments of the function "f", while "tracked_vars" is a set
of all variables being tracked (those with respect to which we need derivatives).

out is the name of the output variable. Assuming at least one argument is tracked,
out will be added to the set of tracked variables.

"first_pass" and "second_pass" are expressions to which the AD with resect to "f" and "A"
will be added.
"first_pass" is an expression of the forward pass, while
"second_pass" is an expression for the reverse pass.
"""
function differentiate!(first_pass, second_pass, tracked_vars, out, f, A, mod, verbose = false)
#    @show f, typeof(f), A, (A .∈ Ref(tracked_vars))
#    @show f, out, A, (A .∈ Ref(tracked_vars))
    if !any(a -> a ∈ tracked_vars, A)
        push!(first_pass.args, Expr(:(=), out, Expr(:call, f, A...)))
        return
    end
    arity = length(A)
    if f ∈ ProbabilityDistributions.DISTRIBUTION_DIFF_RULES
        ProbabilityDistributions.distribution_diff_rule!(mod, first_pass, second_pass, tracked_vars, out, A, f, verbose)
    elseif haskey(SPECIAL_DIFF_RULES, f)
        SPECIAL_DIFF_RULES[f](first_pass, second_pass, tracked_vars, out, A, mod)
#    elseif f isa GlobalRef # TODO: Come up with better system that can use modules.
#        SPECIAL_DIFF_RULES[f.name](first_pass, second_pass, tracked_vars, out, A)
    elseif @capture(f, M_.F_) # TODO: Come up with better system that can use modules.
        F == :getproperty && return
        if F ∈ keys(SPECIAL_DIFF_RULES)
            SPECIAL_DIFF_RULES[F](first_pass, second_pass, tracked_vars, out, A, mod)
        elseif DiffRules.hasdiffrule(M, F, arity)
            apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(M, F, A...), mod)
        elseif F ∈ NOOPDIFFS            
            noopdiff!(first_pass, second_pass, tracked_vars, out, f, A, mod)
        else
            throw("Function $f with arguments $A is not yet supported.")
        end
#        tuple_diff_rule!(first_pass, second_pass, tracked_vars, out, A)
    elseif f ∈ NOOPDIFFS
        noopdiff!(first_pass, second_pass, tracked_vars, out, f, A, mod)
    elseif DiffRules.hasdiffrule(:Base, f, arity)
        apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(:Base, f, A...), mod)
    elseif DiffRules.hasdiffrule(:SpecialFunctions, f, arity)
        apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(:SpecialFunctions, f, A...), mod)
    else # ForwardDiff?
        throw("Function $f with arguments $A is not yet supported.")
        # Or, for now, Zygote for univariate.
#        zygote_diff_rule!(first_pass, second_pass, tracked_vars, out, A, f)
        # throw("Fall back differention rules not yet implemented, and no method yet to handle $f($(A...))")
    end
end



