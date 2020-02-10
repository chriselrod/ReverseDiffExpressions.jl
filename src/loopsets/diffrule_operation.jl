struct DiffRuleOperation
    diffrule::DiffRule
    operations::OffsetArray{Operation,1}
end
function DiffRuleOperation(dr::DiffRule, nparents::Int = num_parents(dr))
    ops = OffsetArray{Operation}(undef, -nparents:last(last(diffrule.sections)))
    DiffRuleOperation(
        dr, ops
    )
end

function DiffRuleOperation(op::Operation, newops::Vector{Operation})
    vparents = parents(op)
    nargs = length(vparents)
    dr = DERIVATIVERULES[InstructionArgs(instruction(op), nargs)]
    ops = OffsetArray{Operation}(undef, -nargs:last(last(dr.sections)))
    for i ∈ -nargs:-1
        ops[i] = newops[identifier(vparents[i + nargs + 1])]
    end
    DiffRuleOperation( dr, ops )
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

function Base.getindex(dro::DiffRuleOperation, i::Int)
    instruction(dro, i), dependencies(dro, i)
end


