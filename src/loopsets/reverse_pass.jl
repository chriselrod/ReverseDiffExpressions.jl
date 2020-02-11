
function reverse_pass!(∂ls::∂LoopSet)
    N = length(∂ls.opsparentsfirst)
    for n ∈ 0:N-1
        i = ∂ls.opsparentsfirst[N - n]
        add_reverse_operation!(∂ls, i)
    end
end

function add_reverse_operation!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold = ∂ls
    ops = operations(lsold)
    op = ops[i]
    
    if isload(op)
        add_load_reverse!(∂ls, i)
        # if istracked(∂ls, op)
        #     adjop = adj(name(op))
        #     ∂ref = ArrayReferenceMeta( ArrayReference( adjop, getindices(op) ), op.ref.loopedindex )
        #     ∂op = Operation(
        #         - 1, adjop, 8, :setindex!, memstore, loopdeps, NODEPENDENCY, Operation[], ∂ref, NODEPENDENCY
        #     )
        #     # backlogged store; wait until it has a parent to add
        #     ∂newops[i] = ∂op
        # end
    elseif iscompute(op) && !isreductcombineinstr(instruction(op))
        add_compute_reverse!(∂ls, i)
    elseif isstore(op)
        add_store_reverse!(∂ls, i)
        # if istracked(∂ls, op)
        #     adjop = adj(name(op))
        #     ∂ref = ArrayReferenceMeta( ArrayReference( adjop, getindices(op) ), op.ref.loopedindex )
        #     ∂op = Operation(
        #         - 1, adjop, 8, :getindex, memload, loopdeps, NODEPENDENCY, Operation[], ∂ref, NODEPENDENCY
        #     )
        #     # backlogged store; wait until it has a parent to add
        #     ∂newops[i] = ∂op
        # end
    # else#if isconstant(op)
        # add_constant_reverse!(∂ls, i)
    end
    
end

function adjref(ref::ArrayReferenceMeta)
    ArrayReferenceMeta(
        ArrayReference(adj(ref.array), ref.indices), ref.loopedindex
    )
end
adjref(op::Operation) = adjref(op.ref)

function add_reverse_input!(ropsargs::Vector{Vector{Operation}}, opold::Operation, opnew::Operation)
    if isreductcombineinstr(opold)
        add_reverse_input_parent!(ropsargs, opold, opnew, 1)
    else
        push!(ropsargs[identifier(opold)], opnew)
    end
    nothing
end
function add_reverse_input_parent!(ropsargs::Vector{Vector{Operation}}, opold::Operation, opnew::Operation, i::Int)
    add_reverse_input!(ropsargs, parents(opold)[i], opnew)
end

function add_constant_reverse!(∂ls::∂LoopSet, i::Int)

end
function add_load_reverse!(∂ls::∂LoopSet, i::Int)
    
end
function add_store_reverse!(∂ls::∂LoopSet, i::Int)
    istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    opold = operations(lsold)[i]
    rops = operations(rls)
    ref = adjref(opold)
    opnew = Operation(
        length(rops), adj(name(opold)), 8, :getindex, memload, loopdependencies(opold), NODEPENDENCY, NOPARENTS, ref, NODEPENDENCY
    )
    # push!(rops, opnew)
    add_load!(rls, opnew)
    add_reverse_input_parent!(ropsargs, opold, opnew, 1)
    nothing
end

function issubset(sub, sup)
    length(sub) < length(sup)
end

function make_updating_failed!(op1, op2)
    updateinstr = get(MAKEUPDATING, op1, nothing)
    updateinstr === nothing && return false
    op1.instruction = updateinstr
    push!(parents(op1), op2)
    true
end

function get_adj_input_op_noreduct!(∂ls::∂LoopSet, ropsargsᵢ::Vector{Operation}, i::Int)
    @unpack rls, diffops, lsold = ∂ls
    oldop = operations(lsold)[i]
    dro = diffops[i]
    rop₁ = first(ropsargsᵢ) # Throws boundserror if length 0
    for j ∈ 2:length(ropsargsᵢ)
        ropⱼ = ropsargsᵢ[j]
        if make_updating_failed!(rop₁, ropⱼ)
            if make_updating_failed!(ropⱼ, rop₁)
                rop₁ = Operation(
                    length(operations(rls)), gensym(:combineadjoints), 8, :vadd, compute, loopdependencies(lsold), Symbol[], [rop₁, ropⱼ], NOTAREFERENCE
                )
                push!(operations(rls), rop₁)
            else # ropⱼ now adds rop₁, so ropⱼ would be the correct op to return
                rop₁ = ropⱼ    
            end
        end
    end
    dro[0] = rop₁
end


function reductzero!(∂ls::∂LoopSet, op)
    instr = instruction(op)
    if instr.instr ∉ (:vmul, :*, :evmul)
        return :zero
    end
    @assert length(parents(op)) == 2
    vparents = parents(op)
    parent1 = vparents[1]
    parent2 = vparents[2]
    if isconstant(parent1)
        
    elseif isconstant(parent2)
    end
    :zero
end

# This method means that we have a reduction.
# We must determine which variables are the reductions, and update parents accordingly
# If a parent performing the reduction is in the `c = a * b` family, we should swap `∂a` defintion of `b` with `c / a`.
# For reduction, ops must also be made updating.
# 
# Strategy of this function is to go through ropsargs, and create reduced/reduce_to ops for all reductions,
# and then to call get_adj_input_op_noreduct!(∂ls::∂LoopSet, ropsargsᵢ, i::Int)
function get_adj_input_op_reduct!(∂ls::∂LoopSet, ropsargsᵢ::Vector{Operation}, i::Int)
    @unpack rls, diffops, lsold = ∂ls
    oldop = operations(lsold)[i]
    loopdeps = loopdependencies(oldop)
    # We need a simple reduce_to target, shareable by all reductions
    mCt = gensym(:targetzero)
    targetzero = add_constant!(ls, gensym(:targetzero), loopdes, mCt, 8, :numericconstant)
    push!(ls.preamble_zeros, (identifier(targetzero), LoopVectorization.IntOrFloat))

    # And a reduction-specific zero init
    for j ∈ eachindex(ropsargsᵢ)
        ropⱼ = ropsargsᵢ[j]
        ropⱼdeps = loopdependencies(ropⱼ)
        length(ropⱼdeps) == length(loopdeps) && continue
        reducedc = [s for s ∈ ropⱼdeps if s ∉ loopdeps]
        # Now, we must
        # [ ] 1. make ropⱼ a reduction, adding or multiplying across the reducedc loops
        # [ ] 2. Create a reduction zero initializer
        # [ ] 3. Create a reduction finalizer (i.e., reduced_/reduce_to)
        # [ ] 4. If reductzero is :one, define derivative as c / a
        zeroinstr = reductzero(ropⱼ)
        reductinit = add_constant!(rls, gensym(:reductzero), loopdeps, name(ropⱼ), 8, :numericconstant)
        reductinit.reduced_children = reducedc
        
        ropsargsᵢ[j] = ropⱼr
    end
    # ldrt = reduceddependencies(lsold)
    
    op = Operation(length(operations(rls)), gensym(:zero), 8, ldrt, )

    push!(rls.preamble_zeros, (length(operations(rls)), LoopVectorization.IntOrFloat))

    # We've reduced all the reduction variables, so no we use the noreduct version.
    get_adj_input_op_noreduct!(∂ls, ropsargsᵢ, i)
end


function update_store_tracker!(∂ls::∂LoopSet, i::Int, oldop::Operation)
    @unpack vartracker, ropsargs, tracked_ops, rls = ∂ls
    adjarrayname = adj(name(oldop.ref))
    if !isdefined(vartracker, adjarrayname)
        define!(vartracker, adjarrayname)
        return
    end
    # adjarrayname is already defined, but now we load from it.
    loadadj = Operation(
        i - 1, gensym(:adjointload), 8, :getindex, memload, loopdependencies(oldop), reduceddependencies(oldop), NOPARENTS, adjref(oldop), reducedchildren(oldop)
    )
    push!(ropsargs[i], loadadj)
    add_load!(rls, loadadj)
    nothing
end


# This function handles combining multiples
# and determining reductions
function get_adj_input_op!(∂ls::∂LoopSet, i::Int)
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    oldop = operations(lsold)[i]
    if isload(oldop)
        update_store_tracker!(∂ls, i, oldop)
    end
    oldop_ld = loopdependencies(oldop)
    ndeps = length(oldop_ld)
    # This function must compute reduction
    ropsargsᵢ = ropsargs[i]
    maxdeps = maximum(length ∘ loopdependencies, ropsargsᵢ)
    if maxdeps > ndeps
        get_adj_input_op_reduct!(∂ls::∂LoopSet, ropsargsᵢ, i)
    else
        get_adj_input_op_noreduct!(∂ls::∂LoopSet, ropsargsᵢ, i)
    end
end
function add_compute_reverse!(∂ls::∂LoopSet, i::Int)
    istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    oldop = operations(lsold)[i]
    rops = operations(rls)

    dro = diffops[i]
    # dro 0 can now be filled in
    sects = sections(dro)
    num_reverse_sections = length(sects) - 1
    nargs = length(sects) - 2
    drops = operations(dro)
    for k ∈ 2:length(sects)
        (k > 2 && !istracked(∂ls, dro[k - 3 - nargs])) && continue
        for j ∈ sects[k]
            instrⱼ, depsⱼ = dro[j]
            if instrⱼ === :adjoint
                drops[j] = drops[first(depsⱼ)]
                continue
            end
            parentsⱼ = drops[depsⱼ]
        end
    end
end

