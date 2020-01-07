
using LoopVectorization: LoopSet, operations, isload, iscompute, isstore, loopdependencies, refname, name, lower, parents,
    Operation

struct ∂LoopSet
    ls::LoopSet
    ∂ls::LoopSet
    visited_ops::Vector{Bool}
    tracked_ops::Vector{Bool}
    tracked_vars::Set{Symbol}
end

function ∂LoopSet(ls::LoopSet, tracked_vars::Set{Symbol})
    nops = length(operations(ls))
    ∂ls = ∂LoopSet(ls, LoopSet(), fill(false, nops), fill(false, nops),  tracked_vars)
    copy!(∂ls.∂ls.loops, ls.loops)
    ∂ls
end
firstpass(∂ls::∂LoopSet) = ∂ls.ls
secondpass(∂ls::∂LoopSet) = ∂ls.∂ls
LoopVectorization.lower(∂ls::∂LoopSet) = lower(firstpass(∂ls))
∂lower(∂ls::∂LoopSet) = lower(secondpass(∂ls))
istracked(∂ls::∂LoopSet, i::Int) = ∂ls.tracked_ops[i]
istracked(∂ls::∂LoopSet, op::Operation) = ∂ls.tracked_ops[identifier(op)]
visited(∂ls::∂LoopSet, i::Int) = ∂ls.visited_ops[i]
visited(∂ls::∂LoopSet, op::Operation) = ∂ls.visited_ops[identifier(op)]
track!(∂ls::∂LoopSet, i::Int) = (∂ls.tracked_ops[i] = true)
track!(∂ls::∂LoopSet, op::Operation) = (∂ls.tracked_ops[identifier(op)] = true)
visit!(∂ls::∂LoopSet, i::Int) = (∂ls.visited_ops[i] = true)
visit!(∂ls::∂LoopSet, op::Operation) = (∂ls.visited_ops[identifier(op)] = true)

function check_if_parents_tracked!(metadata, op::Operation, tracked_vars::Set{Symbol})
    i = identifier(op)
    for opp ∈ parents(op)
        oppid = identifier(opp)
        metadata[oppid,1] || firstvisit!(metadata, opp, tracked_vars)
        if metadata[oppid,2]
            metadata[i,2] = true
            break
        end
    end
end
function firstvisit!(∂ls::∂LoopSet, op::Operation)
    i = identifier(op)
    visit(∂ls, i)
    if isconstant(op)
        if iszero(length(loopdependencies(op)))
            name(op) ∈ tracked_vars && track!(∂ls, i)
        end
    elseif isload(op)
        op.ref.array ∈ tracked_vars && track!(∂ls, i)
    elseif iscompute(op)
        check_if_parents_tracked!(∂ls, op)
    elseif isstore(op)
        check_if_parents_tracked!(metadata, op, tracked_vars)
        tracked(∂ls, i) && push!(∂ls.tracked_vars, op.ref.array)
    end
end

function determine_tracked(∂ls::∂LoopSet, tracked_vars::Set{Symbol})
    foreach(op -> firstvisit!(∂ls, op), operations(firstpass(∂ls)))
    
end

function differentiate_loopset!(ls::LoopSet, tracked_vars::Set{Symbol})
    ∂ls = ∂LoopSet(ls, tracked_vars)
    determine_tracked!(∂ls)
end


