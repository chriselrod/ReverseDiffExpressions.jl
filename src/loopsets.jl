# using much of the name space of LoopVectorization; seems more organized to set it aside.
module LoopSetDerivatives

using ReverseDiffExpressionsBase
using LoopVectorization:
    LoopSet, operations, isload, iscompute, isstore,
    loopdependencies, refname, name, lower, parents,
    Operation, add_op!

struct ∂LoopSet
    ls::LoopSet
    ∂ls::Vector{LoopSet}
    visited_ops::Vector{Bool}
    tracked_ops::Vector{Bool}
    stored_ops::Vector{Int}
    # loads::Vector{Bool}
    # stores::Vector{Bool}
    tracked_vars::Set{Symbol}
    opsparentsfirst::Vector{Int}
end

function copymeta!(lsdest::LoopSet, lssrc::LoopSet)
    append!(lsdest.preamble.args, lssrc.preamble.args)
    append!(lsdest.syms_aliasing_refs, lssrc.syms_aliasing_refs)
    append!(lsdest.refs_aliasing_syms, lssrc.refs_aliasing_syms)
    append!(lsdest.preamble_symsym, lssrc.preamble_symsym)
    append!(lsdest.preamble_symint, lssrc.preamble_symint)
    append!(lsdest.preamble_symfloat, lssrc.preamble_symfloat)
    append!(lsdest.preamble_zeros, lssrc.preamble_zeros)
    append!(lsdest.preamble_ones, lssrc.preamble_ones)
    append!(lsdest.includedarrays, lssrc.includedarrays)
    nothing
end

function ∂LoopSet(ls::LoopSet, tracked_vars::Set{Symbol})
    nops = length(operations(ls))
    ∂ls = ∂LoopSet(LoopSet(ls.mod), LoopSet[], fill(false, nops), fill(false, nops), fill(-1, nops), tracked_vars, sizehint!(Int[], length(ls.operations)))
    resize!(∂ls.ls.operations, length(operations(ls)))
    copymeta!(∂ls.ls, ls)
    determine_parents_first_order!(∂ls, ls)
    determine_stored_computations!(∂ls, ls)
    update_tracked!(∂ls, ls)
    first_pass!(∂ls, ls)
    second_pass!(∂ls, ls)
    ∂ls
end
firstpass(∂ls::∂LoopSet) = ∂ls.ls
secondpass(∂ls::∂LoopSet) = ∂ls.∂ls
secondpass(∂ls::∂LoopSet, i) = ∂ls.∂ls[i]
LoopVectorization.lower(∂ls::∂LoopSet) = lower(firstpass(∂ls))
∂lower(∂ls::∂LoopSet, i) = lower(secondpasses(∂ls, i))
istracked(∂ls::∂LoopSet, i::Int) = ∂ls.tracked_ops[i]
istracked(∂ls::∂LoopSet, op::Operation) = ∂ls.tracked_ops[identifier(op)]
visited(∂ls::∂LoopSet, i::Int) = ∂ls.visited_ops[i]
visited(∂ls::∂LoopSet, op::Operation) = ∂ls.visited_ops[identifier(op)]
track!(∂ls::∂LoopSet, i::Int) = (∂ls.tracked_ops[i] = true)
track!(∂ls::∂LoopSet, op::Operation) = (∂ls.tracked_ops[identifier(op)] = true)
visit!(∂ls::∂LoopSet, i::Int) = (∂ls.visited_ops[i] = true)
visit!(∂ls::∂LoopSet, op::Operation) = (∂ls.visited_ops[identifier(op)] = true)


function append_parent_ids_first!(opsparentsfirst, visited, op)
    visited[identifier(op)] && return
    for opp ∈ parents(op)
        append_parent_ids_first!(opsparentsfirst, visited, opp)
    end
    push!(opsparentsfirst, identifier(op)]
    visitied[identifier(op)] = true
    return
end
function determine_parents_first_order!(opsparentsfirst::Vector{Int}, visited::Vector{Operation}, ops::Vector{Operation})
    for op ∈ ops
        append_parent_ids_first!(opsparentsfirst, visited, op)
    end
    opsparentsfirst
end
function determine_parents_first_order!(∂ls::∂LoopSet, ls::LoopSet)
    visited_ops = fill!(∂ls.visited_ops, false)
    determine_parents_first_order!(∂ls.opsparentsfirst, visited, operations(ls))
end

function determine_stored_computations!(∂ls::∂Loopset, ls::LoopSet)
    stored_ops = ∂ls.stored_ops
    for op ∈ operations(ls)
        if isstore(op)
            parent = first(parents(op))
            stored_ops[identifier(op)] = identifier(op)
            stored_ops[identifier(parent)] = identifier(op)
        end
    end
end

function istracked(op::Operation, tracked_ops::Vector{Bool}, tracked_vars::Set{Symbol})
    for opp ∈ parents(op)
        (tracked_ops[identifier(opp)] || name(opp) ∈ tracked_vars) && return true
    end
    false
end
function update_tracked!(∂ls::∂LoopSet, ls::LoopSet)
    tracked_vars = ∂ls.tracked_vars
    tracked_ops = ∂ls.tracked_ops
    visited_ops = fill!(∂ls.visited_ops, false)
    ops = operations(ls)
    opsparentsfirst = ∂ls.opsparentsfirst
    for i ∈ ls.outter_reductions
        tracked_ops[i] = true
        push!(tracked_vars, name(ops[i]))
    end
    for i ∈ opsparentsfirst
        op = ops[i]
        if istracked(op, tracked_ops, tracked_vars)
            tracked_ops[i] = true
            isstore(op) || push!(tracked_vars, name(op))
        end
    end
end




function add_tracked_compute!()
    nops = length(newops)
    nargs = length(op_parents)
    diffrule = DERIVATIVERULES[InstructionArgs(instr, nargs)]
    retind = first(diffrule.returns) # this will be the instruction that takes the place of op
    for j ∈ first(diffrule.sections)
        instrⱼ = diffrule.instructions[j]
        instrdepsⱼ = diffrule.dependencies[j]
        vparentⱼ = Vector{Operation}(undef, length(instrdepsⱼ))
        for (k,d) ∈ enumerate(instrdepsⱼ)
            @assert (d != 0) & (d ≥ -nargs)
            if d < 0 # we index into parents
                vparentⱼ[k] = op_parents[nargs + 1 + d]
            elseif d > 0
                vparentⱼ[k] = newops[nops + d]
            end
        end
        # calc loopdeps and reduced deps from parents. Special case the situation where op_parents are parents
        if j == retind || instrdepsⱼ == -nargs:-1
            loopdepsⱼ = loopdeps
            reduceddepsⱼ = reduceddeps
            reducedcⱼ = reducedc
        else
            # Plan here is to add each dep that shows up in at least one of the parents
            loopdepsⱼ = Symbol[]; reduceddepsⱼ = Symbol[]; reducedcⱼ = Symbol[]
            for d ∈ loopdeps
                for opp ∈ vparentⱼ
                    if d ∈ loopdependencies(opp)
                        push!(loopdepsⱼ, d)
                        break
                    end
                end
            end
            for d ∈ reduceddeps
                for opp ∈ vparentⱼ
                    if d ∈ reduceddependencies(opp)
                        push!(reduceddepsⱼ, d)
                        break
                    end
                end
            end
            for d ∈ reducedc
                for opp ∈ vparentⱼ
                    if d ∈ reducedchildren(opp)
                        push!(reducedcⱼ, d)
                        break
                    end
                end
            end
        end
        if j == retind
            newops[j] = Operation(
                i - 1, name(op), 8, instrⱼ, compute, 
            )
        else
            push!(newops, Operation(
                length(newops), gensym(:firstpassintermediary), 8, instrⱼ, compute, 
            ))
        end
        # need to see if it is not stored, but required for calculating gradients of tracked vars
        # so we search the diffrule dependencies for j
        if stored_ops[j] == -1 # indicator meaning not stored
            for k ∈ first(diffrule.sections[2]):length(diffrule.dependencies)
                if j ∈ diffrule.dependencies[k]
                    # now we must cache the results of this operation.
                end
            end
        end
    end

end

function add_compte!()
    if tracked_ops[i]
        add_tracked_compute!()
    else
        newops[i] = Operation(
            i - 1, name(op), 8, instr, compute, loopdeps, reduceddeps, op_parents, op.ref, reducedc
        )
    end

end

function first_pass!(∂ls::∂LoopSet, lsold::LoopSet)
    lsnew = ∂ls.ls
    newops = operations(lsnew)
    ops = operations(lsold)
    oldnewaliases = Vector{Int}(undef, length(ops)) # index is old identifier, value is new identifier.
    tracked_ops = ∂ls.tracked_ops
    stored_ops = ∂ls.stored_ops
    for i ∈ ls.opsparentsfirst
        op = ops[i]
        instr = instruction(op)
        loopdeps = loopdependencies(op); reduceddeps = reduceddependencies(op); reducedc = reducedchildren(op);
        if isconstant(op)
            newops[i] = Operation(
                i - 1, name(op), 8, instr, constant, loopdeps, reduceddeps, NOPARENTS, NOTAREFERENCE, reducedc
            )
        elseif isload(op)
            newops[i] = Operation(
                i - 1, name(op), 8, instr, memload, loopdeps, reduceddeps, NOPARENTS, op.ref, reducedc
            )
        else
            op_parents = [newops[identifier(opp)] for opp ∈ parents(op)]
            if iscompute(op)
                add_compte!()
            else#if isstore(op)
                newops[i] = Operation(
                    i - 1, name(op), 8, instr, memstore, loopdeps, reduceddeps, op_parents, op.ref, reducedc
                )
            end
        end
    end
end







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

end # module
