

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


# const var"#TARGET#" = Variable(Symbol("##TARGET##"), Dimensions(Int[],Bool[]),true,0)
# const var"#TARGET#" = Variable(Symbol("##TARGET##"), 0, true)
# const var"#ONE#" = Variable(Symbol("##ONE##"), 0, true)


