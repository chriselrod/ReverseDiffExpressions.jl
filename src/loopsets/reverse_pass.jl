
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
    elseif iscompute(op)
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

function add_constant_reverse!(∂ls::∂LoopSet, i::Int)

end
function add_load_reverse!(∂ls::∂LoopSet, i::Int)
    
end
function add_store_reverse!(∂ls::∂LoopSet, i::Int)
    istracked(∂ls, i) || return
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    opold = operations(lsold)[i]
    rops = operations(rls)
    opnew = Operation(
        length(rops), adj(name(opold)), 8, :getindex, memload, loopdependencies(opold), NODEPENDENCY, NOPARENTS, adjref(opold), NODEPENDENCY
    )
    push!(rops, opnew)
    push!(ropsargs[identifier(first(parents(opold)))], opnew)
    nothing
end

function get_adj_input_op!(∂ls::∂LoopSet, i::Int)
    @unpack rls, lsold, ropsargs, diffops = ∂ls
    # This function must compute reduction
    vdro₀ = ropsargs[i]
    if length(vdro) == 1
        dro[0] = vdro[1]
    elseif length(vdro) > 1
        lastop = vdro[1]
        for j ∈ 2:length(vdro)
            addop = vdro[j]
            # add lastop + addop
        end
        dro[0] = lastop
    else
        throw("Parent operation not yet added in reverse pass.")
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
            parentsⱼ = drops[depsⱼ]

        end
    end
end

