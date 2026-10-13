# Capability traits over Base's informal interfaces. Base is not rewritten:
# the operations are Base's own functions, and conformance is declared for
# families through Base's abstract types, never derived from the methods that
# happen to exist (a Number iterates and indexes, a String indexes by byte,
# and Base's fallbacks exist for every AbstractArray, whether it works or not).
module BaseTraits
using TraitWorld
@trait_module begin

export HasLength, Iterable, Indexable

"A finite number of elements."
@trait HasLength{R} begin
    Base.length(r::R)::Int
end

"The iteration protocol, with the element type the representation declares."
@trait Iterable{R} begin
    Base.iterate(r::R)::Union{Nothing,Tuple{eltype(R),Any}}
    Base.iterate(r::R, s)::Union{Nothing,Tuple{eltype(R),Any}}
end

"Indexing by position 1:length, with the element type the representation declares."
@trait Indexable{R} <: HasLength begin
    Base.getindex(r::R, i::Int)::eltype(R)
end

# Base's families, taken at their documented word
@implement HasLength{A} where {A <: AbstractArray}
@implement HasLength{T} where {T <: Tuple}
@implement HasLength{S} where {S <: AbstractString}
@implement HasLength{D} where {D <: AbstractDict}
@implement HasLength{S} where {S <: AbstractSet}
@implement Iterable{A} where {A <: AbstractArray}
@implement Iterable{T} where {T <: Tuple}
@implement Iterable{S} where {S <: AbstractString}
@implement Iterable{D} where {D <: AbstractDict}
@implement Iterable{S} where {S <: AbstractSet}
@implement Indexable{A} where {A <: AbstractVector}
@implement Indexable{T} where {T <: Tuple}

end
end
