# using much of the name space of LoopVectorization; seems more organized to set it aside.
module LoopSetDerivatives

using ReverseDiffExpressionsBase
using LoopVectorization:
    LoopSet, operations, isload, iscompute, isstore,
    loopdependencies, refname, name, lower, parents,
    Operation, add_op!

struct ∂LoopSet
    ls::LoopSet
    ∂ls::LoopSet
    ∂lschildren::Vector{Vector{Operation}}
    visited_ops::Vector{Bool}
    tracked_ops::Vector{Bool}
    stored_ops::Vector{Int}
    # loads::Vector{Bool}
    # stores::Vector{Bool}
    tracked_vars::Set{Symbol}
    initialized_vars::Set{Symbol}
    opsparentsfirst::Vector{Int}
    ∂ops::Vector{Operation}
    dependingonundefined::Vector{Vector{Tuple{Int,Int}}}
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
function ∂LoopSet(mod, nops, tracked_vars::Set{Symbol})
    ∂LoopSet(
        LoopSet(mod), LoopSet(mod),
        fill(false, nops), fill(false, nops), fill(-1, nops),
        tracked_vars, sizehint!(Int[], nops),
        Vector{Operation}(undef, nops),
        [Tuple{Int,Int}[] for _ ∈ 1:nops]
    )
end
function ∂LoopSet(ls::LoopSet, tracked_vars::Set{Symbol})
    nops = length(operations(ls))
    ∂ls = ∂LoopSet(ls.mod, nops, tracked_vars)
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


struct DiffRuleOperation
    diffrule::DiffRule
    operations::OffsetArray{Operation,1}
end
function DiffRuleOperation(dr::DiffRule, nparents = num_parents(dr))
    ops = OffsetArray{Operation}(undef, -nparents:last(last(diffrule.sections)))
    DiffRuleOperation(
        dr, ops
    )
end

function DiffRuleOperation(op::Operation)
    nargs = length(parents(op))
    dr = DERIVATIVERULES[InstructionArgs(instruction(op), nargs)]
    DiffRuleOperation(dr, nargs)
end
function LoopVectorization.parents(dro::DiffRuleOperation)
    nparents = num_parents(dro.diffrule)
    view(dro.operations[-nparents:-1])
end
LoopVectorization.instruction(dro::DiffRuleOperation, i::Int) = instruction(dro.diffrule, i)
LoopVectorization.operations(dro::DiffRuleOperation) = dro.operations
function returned_ind(dro::DiffRuleOperation, i::Int)
    i == 2 && return typemin(Int)
    dro.diffrule.returns[i - (i > 2)]
end
returned_inds(dro::DiffRuleOperation) = dro.diffrule.returns
section(dro::DiffRuleOperation, i::Int) = dro.diffrule.sections[i]
sections(dro::DiffRuleOperation) = dro.diffrule.sections
dependencies(dro::DiffRuleOperation) = dro.diffrule.dependencies
dependencies(dro::DiffRuleOperation, i::Int) = dro.diffrule.dependencies[i]

function fill_parents(dro::DiffRuleOperation)
    vparentⱼ = Vector{Operation}(undef, num_parents(dro.diffrule))
    instrdepsⱼ = dependencies(diffrule, j)
    ops = operations(dro)
    for (k,d) ∈ enumerate(instrdepsⱼ)
        vparentⱼ[k] = ops[d]
    end
    vparentⱼ
    # for (k,d) ∈ enumerate(instrdepsⱼ)
    #     @assert (d != 0) & (d ≥ -nargs)
    #     if d < 0 # we index into parents
    #         vparentⱼ[k] = op_parents[nargs + 1 + d]
    #     elseif d == retind
    #         vparentⱼ[k] = newops[j]
    #     else # we don't add to the end of the array when d == retind, so those greater must be decremented
    #         vparentⱼ[k] = newops[nops + d - (d > retind)]
    #     end
    # end
end
function determine_dependencies_forward(diffrule::DiffRuleOperation, vparentⱼ::Vector{Operation}, j::Int)
    instr = instruction(diffrule, j)
    instrdeps = dependencies(diffrule, j)
    # calc loopdeps and reduced deps from parents. Special case the situation where op_parents are parents
    if j == retind || instrdepsⱼ == -nargs:-1
        loopdepsⱼ = loopdeps
        reduceddepsⱼ = reduceddeps
        reducedcⱼ = reducedc
    else
        # Plan here is to add each dep that shows up in at least one of the parents
        vparentⱼ = parents(diffrule)
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
    loopdepsⱼ, reduceddepsⱼ reducedcⱼ
end
function determine_dependencies_reverse(diffrule::DiffRuleOperation, vparentⱼ::Vector{Operation}, j::Int)
    instr = instruction(diffrule, j)
    instrdeps = dependencies(diffrule, j)
    # Need to figure out the logic here.
    
    loopdeps, reduceddeps reducedc
end
function add_section_forward!()
    
end
function add_section_reverse!(
    ∂ls::∂LoopSet, dro::DiffRuleOperation, op::Operation, s::Int, referenceops::Vector{Operation}
)
    pls = ∂ls.∂ls; ls = ∂ls.ls
    ops = operations(dro)
    diffops = operations(dro)
    sectionₛ = section(dro, s)
    ∂ops = ∂ls.∂ops
    if s > 2
        # retind will be assigned to ∂parent₍ₛ₋₁₎
        # can find it in ∂ops[identifier(parent₍ₛ₋₁₎)]
        retind = returned_ind(dro, s)
        # either retind will be assigned to ∂ops[identifier(parent₍ₛ₋₁₎)],
        # or it will be promoted to MAKEUPDATING version, or a vadd used to combine.
        parentid = s - 3 + firstindex(ops) # s == 3 corresponds to first parent, thus use firstindex into ops
        assigndeps = loopdependencies(∂ops[identifier(ops[parentid])])
    else#if s == 2 # then we are not defining an op̄
        retind = typemin(Int)
        assigndeps = NODEPENDENCY 
    end
    for i ∈ sectionₛ
        instr = instruction(dro, i)
        deps = dependencies(dro, i)
        if (instr == Instruction(:adjoint) || instr == Instruction(:transpose) || instr == Instruction(:identity))
            @assert length(deps) == 1
            diffops[i] = diffops[first(deps)]
        else
            vparents = Vector{Operation}(undef, length(deps))
            for (j,d) ∈ enumerate(deps)
                d == 0 && continue
                # ops[d] for d != 0 should be assigned; if not will throw error
                vparents[j] = ops[d] 
            end
            loopdeps, reduceddeps, reducedc = determine_dependencies_reverse(dro, vparent, i, retind, assigndeps)
            #id to be corrected later
            diffops[i] = Operation(i-1, name(op), 8, instr, compute, loopdeps, reduceddeps, vparents, NOTAREFERENCE, reducedc)
        end
    end
    if s > 2
        parentid = s - 3 + firstindex(ops) # s == 3 corresponds to first parent, thus use firstindex into ops
        child = ∂ops[identifier(ops[parentid])]
        # which ind of this child's parent's is the newly assigned Operation?
        
    end
end
function add_tracked_compute!(∂lss::∂LoopSet, lsold::LoopSet, op::Operation)
    ls = ∂lss.ls
    ∂ls = ∂lss.∂ls
    ∂ops = ∂ls.∂ops
    newops = operations(ls)
    ∂newops = operations(∂ls)
    # nops = length(newops)
    dro = DiffRuleOperation(op)
    diffops = operations(dro) # ops will be added with ids w/ respect to position in diffops; later these will be corrected to position w/in operations(∂ls)
    i = firstindex(diffops)
    for opp ∈ parents(op)
        diffops[i] = newops[identifier(opp)]
        i += 1
    end
    for (s, sectionₛ) ∈ enumerate(sections(dro))
        # retind = returned_ind(dro, s)
        if s == 1
            add_section_forward!()
        else
            add_section_reverse!()
        end
        ls = s == 1 ? ∂ls.ls : ∂ls.∂ls
        # retind must be handled here, because section could have been skipped
    end
    
    retinds = returns(dro)
    
    retind = first(diffrule.returns) # this will be the instruction that takes the place of op
    
    for j ∈ first(diffrule.sections)
        newopid = if j == retind
            newops[j] = Operation(
                i - 1, name(op), 8, instrⱼ, compute, 
            )
            j
        else
            push!(newops, Operation(
                length(newops), gensym(:firstpassintermediary), 8, instrⱼ, compute, 
            ))
            length(newops)
        end
        # need to see if it is not stored, but required for calculating gradients of tracked vars
        # so we search the diffrule dependencies for j
        if stored_ops[newopid] == -1 # indicator meaning not stored
            for section ∈ @view(diffrule.sections[2:end])
                
            end
            for k ∈ first(diffrule.sections[2]):length(diffrule.dependencies)
                if j ∈ diffrule.dependencies[k]
                    # now we must cache the results of this operation.
                    push!(newops_to_store, newopid)
                    break
                end
            end
        end
    end

end

function add_compute!()
    if tracked_ops[i]
        add_tracked_compute!()
    else
        newops[i] = Operation(
            i - 1, name(op), 8, instr, compute, loopdeps, reduceddeps, op_parents, op.ref, reducedc
        )
    end
end
function add_operation!(∂ls::∂LoopSet, ops::Vector{Operation}, i::Int)
    op = ops[i]
    lsnew = operations(∂ls.ls)
    ∂lsnew = operations(∂ls.∂ls)
    newops = operations(lsnew)
    ∂newops = ∂ls.∂ops#operations(∂lsnew)
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
        if istracked(∂ls, op)
            adjop = adj(name(op))
            ∂ref = ArrayReferenceMeta( ArrayReference( adjop, getindices(op) ), op.ref.loopedindex )
            ∂op = Operation(
                - 1, adjop, 8, :setindex!, memstore, loopdeps, NODEPENDENCY, Operation[], ∂ref, NODEPENDENCY
            )
            # backlogged store; wait until it has a parent to add
            ∂newops[i] = ∂op
        end
    elseif iscompute(op)
        add_compte!()
    else#if isstore(op)
        op_parents = [newops[identifier(opp)] for opp ∈ parents(op)]
        newops[i] = Operation(
            i - 1, name(op), 8, instr, memstore, loopdeps, reduceddeps, op_parents, op.ref, reducedc
        )
        if istracked(∂ls, op)
            adjop = adj(name(op))
            
            ∂ref = ArrayReferenceMeta( ArrayReference( adjop, getindices(op) ), op.ref.loopedindex )
            ∂op = Operation(
                - 1, adjop, 8, :getindex, memload, loopdeps, NODEPENDENCY, Operation[], ∂ref, NODEPENDENCY
            )
            # backlogged store; wait until it has a parent to add
            ∂newops[i] = ∂op
        end
    end
    
end

function first_pass!(∂ls::∂LoopSet, lsold::LoopSet)
    lsnew = ∂ls.ls
    ops = operations(lsold)
    oldnewaliases = Vector{Int}(undef, length(ops)) # index is old identifier, value is new identifier.
    tracked_ops = ∂ls.tracked_ops
    stored_ops = ∂ls.stored_ops
    for i ∈ ls.opsparentsfirst
        add_operation!(∂ls, ops, i)
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
