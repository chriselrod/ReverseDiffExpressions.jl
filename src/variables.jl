

# struct Dimensions
    # sizehints::Vector{Int}
    # sizeexact::Vector{Bool}
# end

mutable struct Variable
    varid::Int
    name::Symbol
    parentfunc::Int#id of Func creating it.
    useids::Vector{Int}#ids of Funcs that use it.
    # dims::Dimensions
    tracked::Bool
    initialized::Bool
    function Variable(name::Symbol, id::Int = 0, tracked = false)
        Variable(id, name, 0, Int[], tracked, false)
    end
end
# Base.ndims(d::Dimensions) = length(d.sizehints)
# Base.ndims(v::Variable) = length(v.dims)
# isscalar(v::Variable) = iszero(ndims(v))
istracked(v::Variable) = v.tracked
LoopVectorization.name(v::Variable) = v.name

# function Base.hash(v::Variable, u::UInt)

# end
# function Base.isequal(v1::Variable, v2::Variable)
#     v1.varid == v2.varid && return true
#     v1.name == v2.name && return true

# end

# const var"#TARGET#" = Variable(Symbol("##TARGET##"), Dimensions(Int[],Bool[]),true,0)
# const var"#TARGET#" = Variable(Symbol("##TARGET##"), 0, true)
# const var"#ONE#" = Variable(Symbol("##ONE##"), 0, true)


