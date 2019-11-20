
# using MacroTools, DiffRules
# using MacroTools: @capture, postwalk, prewalk, @q, striplines
# DiffRules.hasdiffrule(:Base, :exp, 1)
# DiffRules.diffrule(:Base, :exp, :x)
# DiffRules.diffrule(:Base, :^, :x, :y)


const SPECIAL_DIFF_RULE = FunctionWrapper{Nothing,Tuple{Vector{Any},Vector{Any},Set{Symbol},InitializedVarTracker,Symbol,Vector{Any},Symbol}}
const SPECIAL_DIFF_RULES = Dict{Symbol,SPECIAL_DIFF_RULE}()

function exp_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    a = first(A)
    # allocate!(ivt, first_pass, out, mod)
    allocate!(ivt, out)
    push!(first_pass, :($out = $mod.SLEEFPirates.exp($a)))
    a ∈ tracked_vars || return nothing
    push!(tracked_vars, out)
    ∂ = adj(out, a)
    adjout = adj(out)
    adja = adj(a)
    push!(first_pass, :($∂ = $out))
    add_aliases!(ivt, out, ∂) # because aliases that live longer could be defined...
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout)))
    nothing
end
SPECIAL_DIFF_RULES[:exp] = SPECIAL_DIFF_RULE(exp_diff_rule!)
function vexp_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    a = first(A)
    push!(first_pass, :($out = similar($a)))
    allocate!(ivt, first_pass, out, mod)
    push!(first_pass, :($out = $mod.PaddedMatrices.vexp!($out, $a)))
    a ∈ tracked_vars || return nothing
    push!(tracked_vars, out)
    ∂ = adj(out, a)
    adjout = adj(out); adja = adj(a)
    push!(first_pass, :($∂ = $mod.Diagonal($out)))
    add_aliases!(ivt, out, ∂)
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout)))
    nothing
end
SPECIAL_DIFF_RULES[:vexp] = SPECIAL_DIFF_RULE(vexp_diff_rule!)
function log_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    a = first(A)
    # allocate!(ivt, first_pass, out, mod)
    allocate!(ivt, out)
    push!(first_pass, :($out = $mod.SLEEFPirates.log($a)))
    a ∈ tracked_vars || return nothing
    push!(tracked_vars, out)
    adjout = adj(out)
    ∂ = adj(out, a)
    adja = adj(a)
    push!(first_pass, :($∂ = inv($a)))
    allocate!(ivt, first_pass, ∂, mod)
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout)))
    nothing
end
SPECIAL_DIFF_RULES[:log] = SPECIAL_DIFF_RULE(log_diff_rule!)
function plus_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    # push!(first_pass, :($out = Base.FastMath.add_fast($(A...)) ))
    track_out = false
    adjout = adj(out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track_out = true
        adja = adj(a)
        pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $adjout)))
    end
    if track_out
        # allocate!(ivt, first_pass, out, mod)
        allocate!(ivt, out)
        push!(first_pass, :($out = +($(A...)) ))
        push!(tracked_vars, out)
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    else
        push!(first_pass, :($out = +($(A...)) ))
    end
    nothing
end
SPECIAL_DIFF_RULES[:+] = SPECIAL_DIFF_RULE(plus_diff_rule!)
# add is specifically for DistributionsParameters.Target
function add_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    track_out = false
    adjout = adj(out)
    for i ∈ eachindex(A)
        a = A[i]
        a ∈ tracked_vars || continue
        track_out = true
        adja = adj(a)
        pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $adjout)))
    end
    if track_out
        push!(tracked_vars, out)
        # allocate!(ivt, first_pass, out, mod)
        allocate!(ivt, out)
        push!(first_pass, :($out = $mod.SIMDPirates.vadd($(A...))))
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    else
        push!(first_pass, :($out = $mod.SIMDPirates.vadd($(A...))))
    end
    nothing
end
SPECIAL_DIFF_RULES[:vadd] = SPECIAL_DIFF_RULE(add_diff_rule!)
function minus_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    @assert length(A) == 2
    a₁ = A[1]
    a₂ = A[2]
    adjout = adj(out)
    a₁ ∈ tracked_vars && pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a₁)), $adjout)))
    a₂ ∈ tracked_vars && pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a₂)), SIMDPirates.vsub($adjout))))
    track_out = (a₁ ∈ tracked_vars) || (a₂ ∈ tracked_vars)
    if track_out
        push!(tracked_vars, out)
        # allocate!(ivt, first_pass, out, mod)
        allocate!(ivt, out)
        push!(first_pass, :($out = $a₁ - $a₂ ))        
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    else
        push!(first_pass, :($out = $a₁ - $a₂ ))
    end
    nothing
end
SPECIAL_DIFF_RULES[:-] = SPECIAL_DIFF_RULE(minus_diff_rule!)
function inv_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    a = A[1]
    if a ∉ tracked_vars
        push!(first_pass, :($out = inv($a)))
        return nothing
    end
    push!(tracked_vars, out)
    adjout = adj(out)
    ∂ = adj(out, a)
    # allocate!(ivt, first_pass, out, mod)
    # allocate!(ivt, first_pass, ∂, mod)
    allocate!(ivt, out)
    allocate!(ivt, ∂)
    push!(first_pass, :(($out, $∂) = $mod.StructuredMatrices.∂inv($a)))
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a)), $∂, $(adj(out)) )))
    nothing
end
SPECIAL_DIFF_RULES[:inv] = SPECIAL_DIFF_RULE(inv_diff_rule!)
function inv′_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    a = A[1]
    if a ∉ tracked_vars
        push!(first_pass, :($out = $mod.StructuredMatrices.inv′($a)))
        return nothing
    end
    push!(tracked_vars, out)
    adjout = adj(out)
    ∂ = adj(out, a)
    # allocate!(ivt, first_pass, out, mod)
    # allocate!(ivt, first_pass, ∂, mod)
    allocate!(ivt, out)
    allocate!(ivt, ∂)
    push!(first_pass, :(($out, $∂) = $mod.StructuredMatrices.∂inv′($a)))
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a)), $∂, $(out)) ))
    nothing
end
SPECIAL_DIFF_RULES[:inv′] = SPECIAL_DIFF_RULE(inv′_diff_rule!)

function mul_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    @assert length(A) == 2
    a₁ = A[1]
    a₂ = A[2]
    a₁t = a₁ ∈ tracked_vars
    a₂t = a₂ ∈ tracked_vars
    # push!(first_pass, :($out = Base.FastMath.mul_fast($a1, $a2)))
    # (a₁t || a₂t) && allocate!(ivt, first_pass, out, mod)
    (a₁t || a₂t) && allocate!(ivt, out)
    push!(first_pass, :($out = *($a₁, $a₂)))
    (a₁t || a₂t) || return
    push!(tracked_vars, out)
    adjout = adj(out)
    ∂a₁ = adj(out, a₁)
    ∂a₂ = adj(out, a₂)
    add_aliases!(ivt, a₁, ∂a₂)
    add_aliases!(ivt, a₂, ∂a₁)
    # pushfirst!(second_pass, :( $mod.lifetime_end( $adjout ) ) )
    a₁t && pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a₁)), $adjout, $∂a₁ )))
    a₂t && pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($(adj(a₂)), $∂a₂, $adjout )))
    if a₁t && a₂t
        pushfirst!(second_pass, :(($∂a₁,$∂a₂) = $mod.∂mul($a₁, $a₂, Val{(true,true)}())))
    elseif a₁t
        pushfirst!(second_pass, :($∂a₁ = $mod.∂mul($a₁, $a₂, Val{(true,false)}())))
    else#if a₂t
        pushfirst!(second_pass, :($∂a₂ = $mod.∂mul($a₁, $a₂, Val{(false,true)}())))
    end
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    # pushfirst!(second_pass, :($(ProbabilityDistributions.return_expression(return_expr)) = $mod.∂mul($a1, $a2, Val{$track_tup}())))
    nothing
end
SPECIAL_DIFF_RULES[:*] = SPECIAL_DIFF_RULE(mul_diff_rule!)


function itp_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    ∂tup = Expr(:tuple, out)
    adjout = adj(out)
    track_out = false
    track_tup = Expr(:tuple,)
    # we skip the first argument, time.
    for i ∈ 2:length(A)
        a = A[i]
        if a ∈ tracked_vars
            track_out = true
            push!(track_tup.args, true)
            ∂ = adj(out, a)
            adja = adj(a)
            push!(∂tup.args, ∂)
            # allocate!(ivt, first_pass, ∂, mod)
            allocate!(ivt, ∂)
            pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout )))
        else
            push!(track_tup.args, false)
        end
    end
    # allocate!(ivt, first_pass, out, mod)
    allocate!(ivt, out)
    push!(first_pass, :( $(ProbabilityDistributions.return_expression(∂tup)) = $mod.∂ITPExpectedValue($(A...), Val{$track_tup}())))
    if track_out
        push!(tracked_vars, out)
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    end
    nothing
end
SPECIAL_DIFF_RULES[:ITPExpectedValue] = SPECIAL_DIFF_RULE(itp_diff_rule!)

function hierarchical_centering_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    # fourth arg would be Domains, which are not differentiable.
    length(A) == 4 && @assert A[4] ∉ tracked_vars
    func_output = Expr(:tuple, out)
    tracked = ntuple(i -> A[i] ∈ tracked_vars, Val(3))
    if any(tracked)
        push!(tracked_vars, out)
        # allocate!(ivt, first_pass, out, mod)
        allocate!(ivt, out)
    end
    adjout = adj(out)
    for i ∈ 1:3
        a = A[i]
        if tracked[i]
            ∂ = adj(out, a)
            add_aliases!(ivt, a[4-i], ∂)
            push!(func_output.args, ∂)
            adja = adj(a)
            pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout )))
        end
    end
    push!(first_pass, :($func_output = ∂HierarchicalCentering($(A...), Val{$tracked}()) ) )
    if any(tracked)
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    end
    nothing
end
SPECIAL_DIFF_RULES[:HierarchicalCentering] = SPECIAL_DIFF_RULE(hierarchical_centering_diff_rule!)

function tuple_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    adjout = adj(out)
    track = false
    adjointsa = Vector{Union{Symbol,Nothing}}(undef, length(A))
    for i ∈ eachindex(A)
        a = A[i]
        if a ∈ tracked_vars
            track = true
            adja = adj(a)
            # pushfirst!(second_pass, :( $adja = $mod.RESERVED_INCREMENT_SEED_RESERVED($adjout[$i], $adja )))
            adjointsa[i] = adja
        else
            adjointsa[i] = nothing
        end
    end
    push!(first_pass, :($out = Core.tuple($(A...))))
    if track
        push!(tracked_vars, out)
        add_aliases!(ivt, adjointsa, adjout)
        add_aliases!(ivt, A, out)
        push!(first_pass, :($adjout = Core.tuple($(adjointsa...))))
    end
    nothing
end
SPECIAL_DIFF_RULES[:tuple] = SPECIAL_DIFF_RULE(tuple_diff_rule!)

function diagonal_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    @assert length(A) == 1
    a = A[1]
    if a ∈ tracked_vars
        push!(tracked_vars, out)
        adja = adj(a)
        adjout = adj(out)
        add_aliases!(ivt, adja, adjout)
        add_aliases!(ivt, a, out)
        push!(first_pass, :($adjout = $adja))
        # pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adjout, $adja )))
    end
    push!(first_pass, :($out = $mod.Diagonal($a)))
    nothing
end
SPECIAL_DIFF_RULES[:Diagonal] = SPECIAL_DIFF_RULE(diagonal_diff_rule!)

function vec_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    @assert length(A) == 1
    a = A[1]
    push!(first_pass, :($out = vec($a)))
    if a ∈ tracked_vars
        push!(tracked_vars, out)
        adja = adj(a)
        adjout = adj(out)
        add_aliases!(ivt, adja, adjout)
        add_aliases!(ivt, a, out)
        push!(first_pass, :($adjout = vec($adja)))
    end
    nothing
end
SPECIAL_DIFF_RULES[:vec] = SPECIAL_DIFF_RULE(vec_diff_rule!)

function reshape_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    @assert length(A) == 2
    a = A[1]
    shape = A[2]
    push!(first_pass, :($out = reshape($a, $shape)))
    if a ∈ tracked_vars
        push!(tracked_vars, out)
        adja = adj(a)
        adjout = adj(out)
        add_aliases!(ivt, adja, adjout)
        add_aliases!(ivt, a, out)
        # pushfirst!(second_pass, :( $adja = $mod.RESERVED_INCREMENT_SEED_RESERVED(reshape($adjout, $mod.maybe_static_size($a)), $adja) ))
        push!(first_pass, :( $adjout = reshape($adja, $shape)))
    end
    nothing
end
SPECIAL_DIFF_RULES[:reshape] = SPECIAL_DIFF_RULE(reshape_diff_rule!)


function cov_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    # For now, the only method is autoregressive * longitudinal model
    # so we assert that there are precisely three args.
    length(A) == 3 || throw("Please request or add support for different CovarianceMatrix functions!")
#    @assert length(A) == 3
    @assert A[3] ∉ tracked_vars
    func_output = Expr(:tuple, out)
    tracked = ntuple(i -> A[i] ∈ tracked_vars, Val(2))
    if any(tracked)
        push!(tracked_vars, out)
        # allocate!(ivt, first_pass, out, mod)
        allocate!(ivt, out)
    end
    adjout = adj(out)
    for i ∈ 1:2
        a = A[i]
        if tracked[i]
            ∂ = adj(out, a)
            push!(func_output.args, ∂)
            adja = adj(a)
            # allocate!(ivt, first_pass, ∂, mod)
            allocate!(ivt, ∂)
            pushfirst!(second_pass, :( $mod.RESERVED_INCREMENT_SEED_RESERVED!($adja, $∂, $adjout )))
        end
    end
    push!(first_pass, :($func_output = $mod.DistributionParameters.∂CovarianceMatrix($(A...), Val{$tracked}()) ) )
    if any(tracked)
        push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
        allocate!(ivt, first_pass, adjout, mod)
    end
    nothing
end
SPECIAL_DIFF_RULES[:CovarianceMatrix] = SPECIAL_DIFF_RULE(cov_diff_rule!)

# Only views have been implemented so far.
function getindex_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing 
   Ninds = length(A) - 1
    for i ∈ 1:Ninds
        @assert A[i+1] ∉ tracked_vars
    end
    a = first(A)
    if a ∈ tracked_vars
        push!(tracked_vars, out)
        inds = [A[i+1] for i ∈ 1:Ninds]
        adja = adj(a); adjout = adj(out)
        push!(first_pass, Expr(:(=), out, Expr(:call, :view, a, inds...)))
        push!(first_pass, Expr(:(=), adjout, Expr(:call, :view, adja, inds...)))
        add_aliases!(ivt, adja, adjout)
        add_aliases!(ivt, a, out)
        if initialize!(ivt, first_pass, adjout, adja, mod)
            push!(first_pass.args, :(fill!($adja, zero(eltype($adja)))))
        end
    elseif a isa Expr && a.head == :tuple
        #TODO: implement this
        throw("Indexing and unpacking not yet supported.")
    else
        push!(first_pass, :($out = getindex($(A...))))
    end
    nothing
end
SPECIAL_DIFF_RULES[:getindex] = SPECIAL_DIFF_RULE(getindex_diff_rule!)

function rank_update_diff_rule!(
    first_pass::Vector{Any}, second_pass::Vector{Any}, tracked_vars::Set{Symbol}, ivt::InitializedVarTracker, out::Symbol, A::Vector{Any}, mod::Symbol
)::Nothing
    # This function will have to be updated once we add rank updates for things other than
    # a cholesky decomposition.
    Lsym, xsym = A[1], A[2]
    track_L = Lsym ∈ tracked_vars
    track_x = xsym ∈ tracked_vars
    track = track_L | track_x
    push!(tracked_vars, out)
    # track && allocate!(ivt, first_pass, out, mod)
    track && allocate!(ivt, out)
    push!(first_pass, Expr(:(=), out, :(StructuredMatrices.rank_update($(A...)))))
    track || return
    # That is because we differentiate by differentiating the expression:
    # out = chol( L * L' + x * x' )
    adjout = adj(out)
    args = Symbol[out, adjout]
    seedL = adj(Lsym)
    seedLtemp = gensym(seedL)
    if track_L
        # push!(ret.args, seedLtemp)
        push!(args, Lsym)
        # allocate!(ivt, first_pass, Lsym, mod)
        allocate!(ivt, Lsym)
    end
    ∂L = adj(out, Lsym)
    seedx = adj(xsym)
    seedxtemp = gensym(seedx)
    if track_x
        # push!(ret.args, seedxtemp)
        push!(args, xsym)
        # allocate!(ivt, first_pass, xsym, mod)
        allocate!(ivt, xsym)
    end
    ∂x = adj(out, xsym)
    seedchol = gensym(:seedchol)
    if track_L && track_x
        ret = Expr(:tuple, seedLtemp, seedxtemp)
    elseif track_L
        ret = seedLtemp
    else#if track_x
        ret = seedxtemp
    end
    q = quote
        $ret = StructuredMatrices.∂rank_update($(args...))
    end
    track_L && push!(q.args, :($mod.RESERVED_INCREMENT_SEED_RESERVED!($seedL, $seedLtemp)))
    track_x && push!(q.args, :($mod.RESERVED_INCREMENT_SEED_RESERVED!($seedx, $seedxtemp)))
    pushfirst!(second_pass, q)
    push!(first_pass, :($adjout = $mod.alloc_adjoint($out)))
    allocate!(ivt, first_pass, adjout, mod)
    nothing
end
SPECIAL_DIFF_RULES[:rank_update] = SPECIAL_DIFF_RULE(rank_update_diff_rule!)


