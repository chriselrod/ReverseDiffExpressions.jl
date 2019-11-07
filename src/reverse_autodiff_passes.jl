const NOOPDIFFS = Set{Symbol}( ( :AutoregressiveMatrix, :adjoint ))

function noopdiff!(first_pass, second_pass, tracked_vars, out, f, A, mod)
    track = false
    seedout = adj(out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track = true
        seeda = adj(a)
        # pushfirst!(second_pass.args, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(Symbol("##∂target/∂", a, "##")), $∂, $(Symbol("##∂target/∂", out, "##")))))
        pushfirst!(second_pass.args, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!( $seeda, $seedout )))
    end
    track && push!(tracked_vars, out)
    push!(first_pass.args, :($out = $f($(A...))))
    push!(first_pass.args, :($seedout = $mod.alloc_adjoint($out)))
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
    aliases = BiMap()
    postwalk(expr) do x
        if @capture(x, out_ = f_(A__))
            differentiate!(first_pass, second_pass, tracked_vars, out, f, A, mod, aliases, verbose)
        elseif @capture(x, out_ = A_) && isa(A, Symbol)
            throw("Assignment without op should have been eliminated in earlier pass.")
            push!(first_pass.args, x)
            push!(first_pass.args, :($(adj(out)) = $mod.seed(out)))
            pushfirst!(second_pass.args, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(Symbol("###seed###", A)), $(Symbol("###seed###", out)) )) )
            A ∈ tracked_vars && push!(tracked_vars, out)
        end
        x
    end
    aliases
end

function apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, diffrules::NTuple{N}, mod) where {N}
    track_out = false
    push!(first_pass.args, :($out = $f($(A...))))
    seedout = adj(out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track_out = true
        ∂ = adj(out, a)
        push!(first_pass.args, :($∂ = $(diffrules[i])))
        pushfirst!(second_pass.args, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(Symbol("###seed###", a)), $∂, $seedout)))
    end
    if track_out
        push!(tracked_vars, out)
        push!(first_pass.args, :($seedout = $mod.alloc_adjoint($out)))
    end
    nothing
end
function apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, diffrule, mod)
    @assert length(A) == 1 "length(A) == $(length(A)); must equal 1 when passed diffrules are: $(diffrule)"
    track_out = false
    push!(first_pass, :($out = $f($(A...))))
    seedout = adj(out)
    a = A[1]
    a ∈ tracked_vars || return
    ∂ = adj(out, a)
    push!(first_pass.args, :($∂ = $(diffrule)))
    pushfirst!(second_pass.args, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a)), $∂, $seedout)))
    push!(tracked_vars, out)
    push!(first_pass.args, :($seedout = $mod.alloc_adjoint($out)))
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
function differentiate!(first_pass, second_pass, tracked_vars, out, f, A, mod, aliases, verbose = false)
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
        SPECIAL_DIFF_RULES[f](first_pass, second_pass, tracked_vars, out, A, mod, aliases)
#    elseif f isa GlobalRef # TODO: Come up with better system that can use modules.
#        SPECIAL_DIFF_RULES[f.name](first_pass, second_pass, tracked_vars, out, A)
    elseif @capture(f, M_.F_) # TODO: Come up with better system that can use modules.
        F == :getproperty && return
        if F ∈ keys(SPECIAL_DIFF_RULES)
            SPECIAL_DIFF_RULES[F](first_pass, second_pass, tracked_vars, out, A, mod, aliases)
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
    nothing
end



