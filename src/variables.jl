
mutable struct Variable
    varid::Int # 0 is target, 1 is One()
    name::Symbol
    parentfuncs::Vector{Int}#id of Func creating it.
    useids::Vector{Int}#ids of Funcs that use it.
    paireddeps::Vector{Int}
    tracked::Bool
    lowered_count::Int
    # initialized::Bool
    ref::Any
    # function Variable(name::Symbol, id::Int)
        # new(id, name, 0, Int[], false, true)
    # end
    function Variable(name::Symbol, id::Int)
        new(id, name, Int[], Int[], Int[], 0, true)
    end
end
# Base.ndims(d::Dimensions) = length(d.sizehints)
# Base.ndims(v::Variable) = length(v.dims)
# isscalar(v::Variable) = iszero(ndims(v))
istracked(v::Variable) = v.tracked
num_lowered(v::Variable) = v.lowered_count
isinitialized(v::Variable) = num_lowered(v) == length(parents(v))
LoopVectorization.name(v::Variable) = v.name
identifier(v::Variable) = v.varid

LoopVectorization.parents(v::Variable) = v.parentfuncs
hasparent(v::Variable) = !iszero(parent(v))

isref(v::Variable) = isdefined(v, :ref)

function Base.push!(x::Vector{Any}, v::Variable)
    isref(v) ? push!(x, v.ref) : push!(x, v.name)
end
# function Base.pushfirst!(x::Vector{Any}, v::Variable)
#     isref(v) ? pushfirst!(x, v.ref) : pushfirst!(x, v.name)
# end

# function Base.hash(v::Variable, u::UInt)

# end
# function Base.isequal(v1::Variable, v2::Variable)
#     v1.varid == v2.varid && return true
#     v1.name == v2.name && return true

# end

# const var"#TARGET#" = Variable(Symbol("##TARGET##"), Dimensions(Int[],Bool[]),true,0)
# const var"#TARGET#" = Variable(Symbol("##TARGET##"), 0, true)
# const var"#ONE#" = Variable(Symbol("##ONE##"), 0, true)


