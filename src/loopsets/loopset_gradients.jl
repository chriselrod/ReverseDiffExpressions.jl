# using much of the name space of LoopVectorization; seems more organized to set it aside.
module LoopSetDerivatives

using ..ReverseDiffExpressions: Model, diffsym

using ReverseDiffExpressionsBase, LoopVectorization, UnPack, OffsetArrays
using ReverseDiffExpressionsBase: DiffRule, InstructionArgs, DERIVATIVERULES
using LoopVectorization:
    LoopSet, operations, isload, iscompute, isstore, isconstant,
    constant, memload, compute, memstore, instruction,
    loopdependencies, reduceddependencies, reducedchildren,
    vptr, name, lower, parents, identifier,
    Operation,
    add_op!, add_load!, add_store!,
    ArrayReferenceMeta, ArrayReference,
    NOPARENTS, NOTAREFERENCE, NODEPENDENCY
    

include("diffrule_operation.jl")

struct ∂LoopSet
    fls::LoopSet
    rls::LoopSet
    lsold::LoopSet
    tracked_ops::Vector{Bool}
    visited_ops::Vector{Bool}
    fops::Vector{Operation}
    ropsargs::Vector{Vector{Operation}}
    diffops::Vector{DiffRuleOperation}
    stored_ops::Vector{Int}
    opsparentsfirst::Vector{Int}
    temparrays::Vector{ArrayReferenceMeta}
    # model::Model
end
function copyloopmeta!(lsdest::LoopSet, lssrc::LoopSet)
    append!(lsdest.loopsymbols, lssrc.loopsymbols)
    append!(lsdest.loops, lssrc.loops)
end
function copypreamblemeta!(lsdest::LoopSet, lssrc::LoopSet)
    append!(lsdest.preamble.args, lssrc.preamble.args)
    append!(lsdest.prepreamble.args, lssrc.prepreamble.args)end
function copymeta!(lsdest::LoopSet, lssrc::LoopSet)
    copypreamblemeta!(lsdest, lssrc)
    append!(lsdest.syms_aliasing_refs, lssrc.syms_aliasing_refs)
    append!(lsdest.refs_aliasing_syms, lssrc.refs_aliasing_syms)
    append!(lsdest.preamble_symsym, lssrc.preamble_symsym)
    append!(lsdest.preamble_symint, lssrc.preamble_symint)
    append!(lsdest.preamble_symfloat, lssrc.preamble_symfloat)
    append!(lsdest.preamble_zeros, lssrc.preamble_zeros)
    append!(lsdest.preamble_funcofeltypes, lssrc.preamble_funcofeltypes)
    append!(lsdest.includedarrays, lssrc.includedarrays)
    append!(lsdest.outer_reductions, lssrc.outer_reductions)
    copyloopmeta!(lsdest, lssrc)
    nothing
end
function ∂LoopSet_init(lsold::LoopSet)
    mod = lsold.mod; nops = length(operations(lsold))
    ∂LoopSet(
        LoopSet(mod), LoopSet(mod), lsold,
        fill(false, nops), fill(false, nops),
        sizehint!(Operation[], nops),
        [Operation[] for _ ∈ 1:nops],
        # sizehint!(DiffRuleOperation[], nops),
        Vector{DiffRuleOperation}(undef, nops),
        fill(-1, nops), sizehint!(Int[], nops),
        ArrayReferenceMeta[]
    )
end
function ∂LoopSet(lsold::LoopSet, tracked_vars)
    nops = length(operations(lsold))
    ∂ls = ∂LoopSet_init(lsold)
    resize!(∂ls.fls.operations, nops)
    copymeta!(∂ls.fls, lsold)
    copypreamblemeta!(∂ls.rls, lsold)
    copyloopmeta!(∂ls.rls, lsold)
    determine_parents_first_order!(∂ls)
    determine_stored_computations!(∂ls)
    update_tracked!(∂ls, tracked_vars)
    forward_pass!(∂ls)
    reverse_pass!(∂ls)
    ∂ls
end
firstpass(∂ls::∂LoopSet) = ∂ls.fls
secondpass(∂ls::∂LoopSet) = ∂ls.rls
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


function append_parent_ids_first!(opsparentsfirst, visited, op)
    visited[identifier(op)] && return
    for opp ∈ parents(op)
        append_parent_ids_first!(opsparentsfirst, visited, opp)
    end
    push!(opsparentsfirst, identifier(op))
    visited[identifier(op)] = true
    return
end
function determine_parents_first_order!(opsparentsfirst::Vector{Int}, visited::Vector{Bool}, ops::Vector{Operation})
    for op ∈ ops
        append_parent_ids_first!(opsparentsfirst, visited, op)
    end
    opsparentsfirst
end
function determine_parents_first_order!(∂ls::∂LoopSet)
    @unpack lsold, visited_ops, opsparentsfirst = ∂ls
    fill!(visited_ops, false)
    determine_parents_first_order!(opsparentsfirst, visited_ops, operations(lsold))
end

function determine_stored_computations!(∂ls::∂LoopSet)
    @unpack lsold, stored_ops = ∂ls
    for op ∈ operations(lsold)
        if isstore(op)
            parent = first(parents(op))
            opid = identifier(op)
            stored_ops[opid] = opid
            stored_ops[identifier(parent)] = opid
        end
    end
end


function istracked(op::Operation, tracked_ops::Vector{Bool}, tracked_vars::Set{Symbol})
    tracked_ops[identifier(op)] && return true
    (isload(op) && op.ref.ref.array ∈ tracked_vars) && return true
    any(opp -> istracked(opp, tracked_ops, tracked_vars), parents(op))
end
function update_tracked!(∂ls::∂LoopSet, tracked_vars)
    @unpack lsold, tracked_ops, visited_ops, opsparentsfirst = ∂ls
    fill!(visited_ops, false)
    ops = operations(lsold)
    for i ∈ lsold.outer_reductions
        tracked_ops[i] = true
        # track!(vartracker, name(ops[i]))
        # push!(tracked_vars
    end
    for i ∈ opsparentsfirst
        op = ops[i]
        if istracked(op, tracked_ops, tracked_vars)
            tracked_ops[i] = true
            isstore(op) || push!(tracked_vars, name(op))
        end
    end
end


include("forward_pass.jl")
include("reverse_pass.jl")



end # module



