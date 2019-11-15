const NOOPDIFFS = Set{Symbol}( ( :AutoregressiveMatrix, :adjoint ))

function noopdiff!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, f, A, mod::Symbol
)
    track = false
    adjout = adj(out)
    push!(first_pass, :($out = $f($(A...))))
    for i ∈ eachindex(A)
        a = (A[i])::Symbol
        a ∈ tracked_vars || continue
        track = true
        adja = adj(a)
        push!(first_pass, :($adjout = $adja))
        # pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!( $seeda, $seedout )))
    end
    track && push!(tracked_vars, out)
    add_aliases!(ivt, adjout, length(A) == 1 ? adj(first(A)) : adj.(A))
    # push!(first_pass, :($seedout = $mod.alloc_adjoint($out)))
    nothing
end

# function reverse_diff_ifelse!(first_pass, second_pass, tracked_vars, cond, conditionaleval, alternateeval)
    # cond_eval_first_pass = quote end; cond_eval_second_pass = quote end
    # reverse_diff_pass!(cond_eval_first_pass, cond_eval_second_pass, conditionaleval, tracked_vars)
    # alt_eval_first_pass = quote end; alt_eval_second_pass = quote end
    # reverse_diff_pass!(alt_eval_first_pass, alt_eval_second_pass, alternateeval, tracked_vars)
    # push!(first_pass, quote
        # if $cond
            # $cond_eval_first_pass
        # else
            # $alt_eval_first_pass
        # end
    # end)
    # pushfirst!(second_pass, quote
        # if $cond
            # $cond_eval_second_pass
        # else
            # $alt_eval_second_pass
        # end
    # end)
    # nothing
# end

# 

function uninitialize_args!(second_pass, ivt::InitializedVarTracker, mod)
    for (i,ex) ∈ enumerate(second_pass)
        if @capture(ex, MOD_.RESERVED_INCREMENT_SEED_RESERVED!(S_, args__))
            q = @q begin end
            if initialize!(ivt, q.args, S, S, mod)
                second_pass[i] = :($mod.RESERVED_INCREMENT_SEED_RESERVED!($mod.uninitialized($S), $(args...)))
            elseif length(q.args) > 0
                # branch only possible if initialize is false
                # means we are adding some zero_initialize! statements
                push!(q.args, ex)
                second_pass[i] = q
            end
        end
    end
end
function free_args!(pass::Vector{Any}, ivt::InitializedVarTracker, mod)
    deallocate = Symbol[]
    for i ∈ eachindex(pass)
        j = length(pass) + 1 - i # reverse
        expr = pass[j]
        if expr isa Expr
            postwalk(expr) do ex
                if ex isa Symbol && isallocated(ivt, ex)
                    deallocate!(ivt, deallocate, ex, ex) # Each deallocate! deallocates entire alias tree, so we wont deallocate again earlier in the expression
                end
                ex
            end
            if length(deallocate) > 0
                q = Expr(:block, expr)
                while length(deallocate) > 0
                    push!(q.args, :($mod.lifetime_end!($(pop!(deallocate)))))
                end
                pass[j] = q
            end
        end
    end
end


function reverse_diff_pass!(first_pass::Vector{Any}, second_pass::Vector{Any}, expr, tracked_vars, mod, verbose = false)
    ivt = InitializedVarTracker()
    postwalk(expr) do x
        if @capture(x, out_ = f_(A__))
            differentiate!(first_pass, second_pass, tracked_vars, ivt, out, f, A, mod, verbose)
        elseif @capture(x, out_ = A_) && isa(A, Symbol)
            throw("Assignment without op should have been eliminated in earlier pass.")
            push!(first_pass, x)
            push!(first_pass, :($(adj(out)) = $mod.seed(out)))
            pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(Symbol("###seed###", A)), $(Symbol("###seed###", out)) )) )
            A ∈ tracked_vars && push!(tracked_vars, out)
        end
        x
    end
    # @show ivt.initialized
    uninitialize_args!(second_pass, ivt, mod) # make sure adjoints are uninitialized on first write
    free_args!(second_pass, ivt, mod) 
    free_args!(first_pass, ivt, mod) 
end

function apply_diff_rule!(first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars, out, f, A, diffrules::NTuple{N}, mod) where {N}
    track_out = false
    push!(first_pass, :($out = $f($(A...))))
    seedout = adj(out)
    for i ∈ eachindex(A)
        a = (A[i])::Symbol
        a ∈ tracked_vars || continue
        track_out = true
        ∂ = adj(out, a)
        push!(first_pass, :($∂ = $(diffrules[i])))
        pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(Symbol("###seed###", a)), $∂, $seedout)))
    end
    if track_out
        push!(tracked_vars, out)
        push!(first_pass, :($seedout = $mod.alloc_adjoint($out)))
    end
    nothing
end
function apply_diff_rule!(first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars, out, f, A, diffrule, mod)
    @assert length(A) == 1 "length(A) == $(length(A)); must equal 1 when passed diffrules are: $(diffrule)"
    track_out = false
    push!(first_pass, :($out = $f($(A...))))
    seedout = adj(out)
    a = (A[1])::Symbol
    a ∈ tracked_vars || return
    ∂ = adj(out, a)
    push!(first_pass, :($∂ = $(diffrule)))
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a)), $∂, $seedout)))
    push!(tracked_vars, out)
    push!(first_pass, :($seedout = $mod.alloc_adjoint($out)))
    nothing
end

function ∂evaluate_rule!(first_pass, second_pass, tracked_vars, out, f, A, mod)
    track = Expr(:tuple, )
    track_out = false
    for a ∈ A
        if a ∈ tracked_vars
            track_out = true
            push!(track.args, true)
        else
            push!(track.args, false)
        end
    end
    adjout = adj(out)
    if !track_out
        push!(first_pass, Expr(:(=), out, Expr(:call, f, A...)))
        return
    end
    pullback = gensym(:pullback)
    push!(first_pass, Expr(:(=), Expr(:tuple, out, pullback), Expr(:call, :($mod.∂evaluate), :(Val{$track}()), f, A...)))
    push!(tracked_vars, out)
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    ∂ = gensym(:∂)
    for (n,a) ∈ enumerate(reverse(A))
        a ∈ tracked_vars || continue
        pushfirst!(second_pass, Expr(:call, :($mod.RESERVED_INCREMENT_SEED_RESERVED!), adj(a), :(@inbounds $∂[$(length(A) + 1 - n)])))
    end
    pushfirst!(second_pass, Expr(:(=), :∂, Expr(:call, pullback, adjout)))
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
function differentiate!(
    first_pass::Vector{Any}, second_pass::Vector{Any},
    tracked_vars::Set{Symbol}, ivt::InitializedVarTracker,
    out::Symbol, f, A::Vector{Any}, mod, verbose::Bool = false
)
#    @show f, typeof(f), A, (A .∈ Ref(tracked_vars))
#    @show f, out, A, (A .∈ Ref(tracked_vars))
    if !any(a -> a ∈ tracked_vars, A)
        push!(first_pass, Expr(:(=), out, Expr(:call, f, A...)))
        return
    end
    arity = length(A)
    if f ∈ ProbabilityDistributions.DISTRIBUTION_DIFF_RULES
        ProbabilityDistributions.distribution_diff_rule!(ivt, first_pass, tracked_vars, mod, out, A, f, verbose)
    elseif haskey(SPECIAL_DIFF_RULES, f)
        SPECIAL_DIFF_RULES[f](first_pass, second_pass, tracked_vars, ivt, out, A, mod)
    elseif @capture(f, M_.F_) # TODO: Come up with better system that can use modules.
        F == :getproperty && return
        if F ∈ keys(SPECIAL_DIFF_RULES)
            SPECIAL_DIFF_RULES[F](first_pass, second_pass, tracked_vars, ivt, out, A, mod)
        elseif DiffRules.hasdiffrule(M, F, arity)
            apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(M, F, A...), mod)
        elseif F ∈ NOOPDIFFS            
            noopdiff!(first_pass, second_pass, tracked_vars, ivt, out, f, A, mod)
        else
            throw("Function $f with arguments $A is not yet supported.")
        end
#        tuple_diff_rule!(first_pass, second_pass, tracked_vars, out, A)
    elseif f ∈ NOOPDIFFS
        noopdiff!(first_pass, second_pass, tracked_vars, ivt, out, f, A, mod)
    elseif DiffRules.hasdiffrule(:Base, f, arity)
        apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(:Base, f, A...), mod)
    elseif DiffRules.hasdiffrule(:SpecialFunctions, f, arity)
        apply_diff_rule!(first_pass, second_pass, tracked_vars, out, f, A, DiffRules.diffrule(:SpecialFunctions, f, A...), mod)
    else
        ∂evaluate_rule!(first_pass, second_pass, tracked_vars, out, f, A, mod)
    end
    nothing
end



