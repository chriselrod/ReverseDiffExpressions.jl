
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
    if isconstant(op)
        add_constant_reverse!(∂ls, i)
    elseif isload(op)
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
    else#if isstore(op)
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
    end
    
end

function add_constant_reverse!(∂ls::∂LoopSet, i::Int)

end
function add_load_reverse!(∂ls::∂LoopSet, i::Int)

end
function add_store_reverse!(∂ls::∂LoopSet, i::Int)

end

function add_compute_reverse!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold, diffops = ∂ls
    oldop = operations(lsold)[i]
    newops = operations(fls)
    
    diffops[i] = dro = DiffRuleOperation(oldop, newops)
    drops = operations(dro)
    
    retind = returned_ind(dro, 1)
    forward_section = section(dro, 1)
    @assert retind ∈ forward_section # For now
    for j ∈ forward_section
        instrⱼ, depsⱼ = dro[j]
        parentsⱼ = drops[depsⱼ]

        loopdeps, reduceddeps, reducedc = determine_dependencies_forward(oldop, dro, j)
        if j == retind
            newops[j] = Operation(
                j - 1, name(op), 8, instrⱼ, compute, loopdeps, reduceddeps, parentsⱼ, NOTAREFERENCE, reducedc
            )
        else
            push!(newops, Operation(
                length(newops), name(op), 8, instrⱼ, compute, loopdeps, reduceddeps, parentsⱼ, NOTAREFERENCE, reducedc
            ))
        end
    end
end

