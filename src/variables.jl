

# struct Dimensions
    # sizehints::Vector{Int}
    # sizeexact::Vector{Bool}
# end

mutable struct Variable
    varid::Int
    name::Symbol
    # dims::Dimensions
    tracked::Bool
    initialized::Bool
end
# Base.ndims(d::Dimensions) = length(d.sizehints)
# Base.ndims(v::Variable) = length(v.dims)
# isscalar(v::Variable) = iszero(ndims(v))
istracked(v::Variable) = v.tracked
LoopVectorization.name(v::Variable) = v.name


# const var"#TARGET#" = Variable(Symbol("##TARGET##"), Dimensions(Int[],Bool[]),true,0)
const var"#TARGET#" = Variable(0, Symbol("##TARGET##"), true, false)



