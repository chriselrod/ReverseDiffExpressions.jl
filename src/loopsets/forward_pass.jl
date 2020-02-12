
function first_pass!(∂ls::∂LoopSet)
    for i ∈ ∂ls.opsparentsfirst
        add_forward_operation!(∂ls, i)
    end
end

function add_forward_operation!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold = ∂ls
    ops = operations(lsold)
    newops = operations(fls)
    op = ops[i]
    instr = instruction(op)
    if isconstant(op)
        newops[i] = Operation(
            i - 1, name(op), 8, instr, constant, loopdependencies(op), reduceddependencies(op), NOPARENTS, NOTAREFERENCE, reducedchildren(op)
        )
    elseif isload(op)
        loadparents = if length(parents(op)) == 0
            NOPARENTS
        else
            [newops[identifier(opp)] for opp ∈ parents(op)]
        end
        newops[i] = Operation(
            i - 1, name(op), 8, instr, memload, loopdependencies(op), reduceddependencies(op), loadparents, op.ref, reducedchildren(op)
        )
    elseif iscompute(op)
        add_compute!(∂ls, i)
    else#if isstore(op)
        op_parents = [newops[identifier(opp)] for opp ∈ parents(op)]
        newops[i] = Operation(
            i - 1, name(op), 8, instr, memstore, loopdependencies(op), reduceddependencies(op), op_parents, op.ref, reducedchildren(op)
        )
    end
end

function add_compute_untracked!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold = ∂ls
    opold = operations(lsold)[i]
    newops = operations(fls)
    vparents = [newops[identifier(opp)] for opp ∈ parents(opold)]
    newops[i] = Operation(
        i - 1, name(opold), 8, instruction(opold), compute, loopdependencies(opold), reduceddependencies(oldold), vparents, NOTAREFERENCE, reducedchildren(opold)
    )
    nothing
end
function add_compute!(∂ls::∂LoopSet, i::Int)
    @unpack fls, lsold, diffops, tracked_ops = ∂ls
    tracked_ops[i] || add_compute_untracked!(∂ls, i)
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
        op = Operation(
            length(newops), name(op), 8, instrⱼ, compute, loopdeps, reduceddeps, parentsⱼ, NOTAREFERENCE, reducedc
        )
        if j == retind
            op.identifier = identifier(oldop)
            newops[identifier(oldop)] = op
        else
            push!(newops, op)
        end
        drops[j] = op
    end
    nothing
end
function combinedeps!(f, totalloopdeps::AbstractVector{T}, opdeps, drops) where {T}
    individualloopdeps = T[]
    for d ∈ totalloopdeps
        for j ∈ opdeps
            if d ∈ f(drops[j])
                push!(individualloopdeps, d)
                break
            end
        end
    end
    individualloopdeps
end

function determine_dependencies_forward(oldop, dro, j)
    @unpack lsold = ∂ls
    loopdeps = loopdependencies(oldop);
    reduceddeps = reduceddependencies(oldop);
    reducedc = reducedchildren(oldop);
    length(section) == 1 && return loopdeps, reduceddeps, reducedc

    drops = operations(dro)
    instrⱼ, instrdepsⱼ = dro[j]
    nargs = -firstindex(dro)
    retind = returned_ind(dro, 1)
    # calc loopdeps and reduced deps from parents. Special case the situation where op_parents are parents
    if j == retind || instrdepsⱼ == -nargs:-1
        return loopdeps, reduceddeps, reducedc
    end
    # Plan here is to add each dep that shows up in at least one of the parents
    loopdepsⱼ = combineddeps(loopdependencies, loopdeps, instrdepsⱼ, drops)
    reduceddepsⱼ = combineddeps(reduceddependencies, reduceddeps, instrdepsⱼ, drops)
    reducedcⱼ = combineddeps(reducedchildren, reducedc, instrdepsⱼ, drops)
    
    loopdepsⱼ, reduceddepsⱼ, reducedcⱼ
end

