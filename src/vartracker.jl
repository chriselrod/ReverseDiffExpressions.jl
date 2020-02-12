
struct IntSymbolSet
    dict::Dict{Symbol,Int}
    vec::Vector{Symbol}
end
IntSymbolSet() = IntSymbolSet(Dict{Symbol,Int}(), Symbol[])
Base.getindex(iss::IntSymbolSet, s::Symbol) = iss.dict[s]
Base.getindex(iss::IntSymbolSet, i::Integer) = iss.vec[i]
Base.length(iss:IntSymbolSet) = legnth(iss.vec)
function Base.push!(iss::IntSymbolSet, s::Symbol)
    @unpack dict, vec = iss
    push!(vec, s)
    dict[s] = length(vec)
    s
end

struct VariableTracker
    variables::Vector{Variable}
    varlookup::IntSymbolSet
    # constantvars::Vector{Variable}
    # constant::IntSymbolSet
end

VariableTracker() = VariableTracker(Variable[], Variable[], IntSymbolSet(), IntSymbolSet())

Base.getindex(vt::VariableTracker, i::Integer) = vt.variables[i]
Base.getindex(vt::VariableTracker, s::Symbol) = vt.variables[vt.varlookup[s]]

function add_tracked!(vt::VariableTracker, s::Symbol)
    @unpack variables, varlookup = vt
    push!(varlookup, s)
    push!(variables, Variable(length(varlookup), s, true, false))
end

