
function reverse_pass!(∂ls::∂LoopSet)
    N = length(∂ls.opsparentsfirst)
    # @show ∂ls.opsparentsfirst
    for i ∈ ∂ls.lsold.outer_reductions
        ∂ls.tracked_ops[i] && add_reverse_operation!(∂ls, i)
    end
    for n ∈ 0:N-1
        i = ∂ls.opsparentsfirst[N - n]
        ∂ls.tracked_ops[i] && add_reverse_operation!(∂ls, i)
    end
end

function add_reverse_operation!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold = ∂ls
    ops = operations(lsold)
    op = ops[i]
    # @show op
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
    elseif iscompute(op) && !isreductcombineinstr(op)
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
    LoopVectorization.ArrayReferenceMeta(LoopVectorization.ArrayReference(diffsym(ref.ref.array), ref.ref.indices), ref.loopedindex)
end
adjref(op::Operation) = adjref(op.ref)

isreductcombineinstr(op::Operation) = op.instruction.instr === :identity
function add_reverse_input!(ropsargs::Vector{Vector{Operation}}, opold::Operation, opnew::Operation)
    if isreductcombineinstr(opold) # changed how this is handled...
        add_reverse_input_parent!(ropsargs, opold, opnew, 1)
    else
        push!(ropsargs[identifier(opold)], opnew)
    end
    nothing
end
# Inserts the parent in ropsargs vector so that it may be accessed
function add_reverse_input_parent!(ropsargs::Vector{Vector{Operation}}, opold::Operation, opnew::Operation, i::Int)
    add_reverse_input!(ropsargs, parents(opold)[i], opnew)
end

# function add_constant_reverse!(∂ls::∂LoopSet, i::Int) end

# Store an adjoint
function add_load_reverse!(∂ls::∂LoopSet, i::Int)
    # istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs = ∂ls
    opold = operations(lsold)[i]
    rops = operations(rls)
    ref = adjref(opold)
    vparents = [get_adj_input_op!(∂ls, i)]
    opnew = Operation(
        length(rops), diffsym(name(opold)), 8, :setindex!, memstore, loopdependencies(opold), NODEPENDENCY, vparents, ref
    )
    add_store!(rls, opnew)
    nothing
end
# Reverse stores have no parents.
function add_store_reverse!(∂ls::∂LoopSet, i::Int)
    # istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs = ∂ls
    opold = operations(lsold)[i]
    rops = operations(rls)
    ref = adjref(opold)
    opnew = Operation(
        length(rops), diffsym(name(opold)), 8, :getindex, memload, loopdependencies(opold), NODEPENDENCY, NOPARENTS, ref, NODEPENDENCY
    )
    # push!(rops, opnew)
    add_load!(rls, opnew)
    add_reverse_input_parent!(ropsargs, opold, opnew, 1)
    nothing
end

function issubset(sub, sup)
    length(sub) < length(sup)
end

function make_updating_failed!(op₁::Operation, op₂::Operation)
    iscompute(op₁) || return true
    instr = instruction(op₁)
    if instr === :reduce_to_add
        op₁.instruction = :reduced_add
        parents(op₁)[2] = op₂
        return false       
    end
    updateinstr = get(ReverseDiffExpressionsBase.MAKEUPDATING, instr, nothing)
    updateinstr === nothing && return true
    op₁.instruction = updateinstr
    pushfirst!(parents(op₁), op₂)
    false
end
function make_updating!(ls::LoopSet, op₁::Operation, op₂::Operation, loopdeps = loopdependencies(op₂))
    if make_updating_failed!(op₁, op₂)
        op₃ = Operation(
            length(operations(ls)), gensym(:combineadjoints), 8, :vadd, compute, loopdeps, Symbol[], [op₁, op₂], NOTAREFERENCE
        )
        push!(operations(ls), op₃)
        op₃
    else
        op₁
    end
end

function get_adj_input_op!(∂ls::∂LoopSet, ropsargsᵢ::Vector{Operation}, i::Int)
    @unpack rls, lsold = ∂ls
    oldop = operations(lsold)[i]
    rop₁ = first(ropsargsᵢ) # Throws boundserror if length 0
    for j ∈ 2:length(ropsargsᵢ)
        ropⱼ = ropsargsᵢ[j]
        if make_updating_failed!(rop₁, ropⱼ)
            rop₁ = make_updating!(rls, ropⱼ, rop₁, loopdependencies(oldop))
        end
    end
    rop₁
end

# function LoopVectorization.matches(v1, v2)
# function matches(v1, v2)
#     length(v1) == length(v2) || return false
#     if length(v1) == 0
#         return true
#     elseif length(v1) == 1
#         first(v1) == first(v2) && return true
#     elseif length(v1) == 2
#         v11 = v1[1]
#         v12 = v1[2]
#         v21 = v2[1]
#         v22 = v2[2]
#         if v11 == v21 && v12 == v22
#             return true
#         elseif v11 == v22 && v12 == v21
#             return true
#         else
#             return false
#         end
#     elseif v1 == v2
#         return true
#     else# trying to avoid sort
#         return sort(v1) == sort(v2)
#     end
# end

# function reductzero!(∂ls::∂LoopSet, op, reducedc)
#     instr = instruction(op)
#     # If there are different numbers of arguments...
#     vparents = parents(op)
#     length(vparents) == 2 || return :zero
#     parent1 = vparents[1]
#     parent2 = vparents[2]
#     mulops = :(:vmul, :*, :evmul)
#     if isconstant(parent1) && matches(reducedchildren(parent1), reducedc)
        
#     elseif isconstant(parent2) && matches(reducedchildren(parent2), reducedc)
        
#     end
#     :zero
# end

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
    targetzero = LoopVectorization.add_constant!(rls, gensym(:targetzero), loopdeps, mCt, 8, :numericconstant)
    push!(rls.preamble_zeros, (identifier(targetzero), LoopVectorization.IntOrFloat))
    isouterreduction = length(loopdeps) == 0
    # And a reduction-specific zero init
    for j ∈ eachindex(ropsargsᵢ)
        ropⱼ = ropsargsᵢ[j]
        ropⱼdeps = loopdependencies(ropⱼ)
        length(ropⱼdeps) == length(loopdeps) && continue
        reducedc = [s for s ∈ ropⱼdeps if s ∉ loopdeps]
        # Now, we must
        # [x] 1. make ropⱼ a reduction, adding across the reducedc loops
        # [x] 2. Create a reduction zero initializer
        # [x] 3. Create a reduction finalizer (i.e., reduced_/reduce_to)
        append!(reduceddependencies(ropⱼ), reducedc)
        reductinit = LoopVectorization.add_constant!(rls, gensym(:reductzero), loopdeps, name(ropⱼ), 8, :numericconstant)
        reductinit.reduced_children = reducedc
        opcomb = make_updating!(rls, ropⱼ, reductinit)
        if isouterreduction
            push!(rls.outer_reductions, identifier(opcomb))
            ropsargsᵢ[j] = opcomb
        else
            # ropⱼr = Operation(length(operations(rls)), gensym(:reduct), 8, :reduce_to_add, compute, loopdeps, reducedc, [opcomb, targetzero])
            ropⱼr = Operation(length(operations(rls)), gensym(:reduct), 8, :identity, compute, loopdeps, reducedc, [opcomb])
            push!(operations(rls), ropⱼr)
            ropsargsᵢ[j] = ropⱼr
        end
    end
    # We've reduced all the reduction variables, so no we use the noreduct version.
    get_adj_input_op!(∂ls, ropsargsᵢ, i)
end

function get_adj_input_op_expand!(∂ls::∂LoopSet, ropsargsᵢ::Vector{Operation}, i::Int)
    @unpack rls, diffops, lsold = ∂ls
    oldop = operations(lsold)[i]
    loopdeps = loopdependencies(oldop)
    reduceddeps = reduceddependencies(oldop)
    for j ∈ eachindex(ropsargsᵢ)
        ropⱼ = ropsargsᵢ[j]
        instrⱼ = instruction(ropⱼ)
        if instrⱼ.instr ∉ (:*, :vmul, :evmul)
            continue
        end
        # I don't think I have to copy oldop? Why not just reuse it?
        push!(operations(rls), oldop)
        op = Operation(length(operations(rls)), gensym(:prodgrad), 8, :/, compute, loopdeps, reduceddeps, [ropⱼ, oldop])
        push!(operations(rls), op)
        ropsargsᵢ[j] = op
    end
    get_adj_input_op!(∂ls, ropsargsᵢ, i)
end

function update_store_tracker!(∂ls::∂LoopSet, i::Int, oldop::Operation)
    @unpack ropsargs, tracked_ops, rls = ∂ls
    adjarrayname = diffsym(name(oldop.ref))
    # @unpack model, ropsargs, tracked_ops, rls = ∂ls
    # if !isdefined(model, adjarrayname)
    #     define!(model, adjarrayname)
    #     return
    # end
    # adjarrayname is already defined, but now we load from it.
    loadadj = Operation(length(operations(rls)), gensym(:adjointload), 8, :getindex, memload, loopdependencies(oldop), reduceddependencies(oldop), NOPARENTS, adjref(oldop), reducedchildren(oldop))
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
    # @show rls.operations
    # @show ropsargs oldop ropsargsᵢ, i
    if maximum(length ∘ loopdependencies, ropsargsᵢ) > ndeps
        get_adj_input_op_reduct!(∂ls, ropsargsᵢ, i)
    elseif minimum(length ∘ loopdependencies, ropsargsᵢ) < ndeps
        get_adj_input_op_expand!(∂ls, ropsargsᵢ, i)
    else
        get_adj_input_op!(∂ls, ropsargsᵢ, i)
    end
end

# This function indexes the operations vector of the DiffRuleOperation to return
# the operation corresponding to dep.
# It checks if that operation is from the reverse-loop. If it is not (if it is from the forward loop)
# it add a load operation to the reverse loop and return that.
# If the operation must be loaded in the reverse loop, it also checks if it was already stored in the forward loop.
# If it wasn't, it adds a store operation to the forward loop.
function get_op_from_deriv_op_vec!(∂ls::∂LoopSet, dro::DiffRuleOperation, dep::Int)
    @unpack fls, rls, lsold, ropsargs, diffops = ∂ls
    sects = sections(dro)
    drops = operations(dro)
    fls_boundary = first(sects[2])
    dop = drops[dep]
    if !iszero(dep) && dep < fls_boundary
        # Then we need to check if the operation has been stored. If not, we must add a store to the previous loop.
        dopid = identifier(dop)
        storeid = ∂ls.stored_ops[dopid]
        # @show storeid dop
        ldref = loopdependencies(dop)
        if isload(dop)
            mref = dop.ref
        elseif storeid == -1
            storeop = LoopVectorization.add_simple_store!(fls, dop, ArrayReference(gensym(:temporaryarray),ldref), 8)
            mref = storeop.ref
            push!(∂ls.temparrays, storeop.ref)
            storeid = identifier(storeop)
            ∂ls.stored_ops[identifier(dop)] = storeid
        else
            mref = operations(fls)[storeid].ref
        end
        # Then we must cse-load it.
        dop = LoopVectorization.add_simple_load!(rls, name(dop), mref, ldref, 8)
    end
    dop
end
function mergedeps(ops::Vector{Operation})
    ldref = copy(loopdependencies(first(ops)))
    rdref = copy(reduceddependencies(first(ops)))
    for op ∈ @view(ops[2:end])
        LoopVectorization.mergesetv!(ldref, loopdependencies(op))
        LoopVectorization.mergesetv!(rdref, reduceddependencies(op))
    end
    ldref, rdref
end

function add_compute_reverse!(∂ls::∂LoopSet, i::Int)
    istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    oldop = operations(lsold)[i]
    rops = operations(rls)
    dro = diffops[i]
    # @show i, dro
    retinds = returned_inds(dro)
    # dro 0 can now be filled in
    sects = sections(dro)
    num_reverse_sections = length(sects) - 1
    nargs = length(sects) - 2
    drops = operations(dro)
    drops[0] = get_adj_input_op!(∂ls, i)
    # @show rops
    for k ∈ 2:length(sects)
        # check if the final return of the section is tracked, if not, continue
        # k > 2 && @show drops[k - nargs - 3]
        (k > 2 && !istracked(∂ls, drops[k - nargs - 3])) && continue
        for j ∈ sects[k]
            instrⱼ, depsⱼ = dro[j]
            # @show j, instrⱼ, depsⱼ
            if instrⱼ === :adjoint
                drops[j] = drops[first(depsⱼ)]
                continue
            end
            parentsⱼ = Vector{Operation}(undef, length(depsⱼ))
            for (d,dep) ∈ enumerate(depsⱼ)
                parentsⱼ[d] = get_op_from_deriv_op_vec!(∂ls, dro, dep)
            end
            ldref, rdref = mergedeps(parentsⱼ)
            op = Operation(length(rops), gensym(:reverseop), 8, instrⱼ, compute, ldref, rdref, parentsⱼ)
            drops[j] = LoopVectorization.pushop!(rls, op)
        end
        if k > 2
            # We have to get_op_from_deriv_op_vec, because the return may have been computed in the first pass; e.g. exp
            add_reverse_input_parent!(ropsargs, oldop, get_op_from_deriv_op_vec!(∂ls, dro, retinds[k-1]), k-2)
        end
    end
end

