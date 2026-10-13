# Rule 5, delegation through package extensions.
#   julia --startup-file=no --project=poc/world/delegation/env poc/world/delegation/delegation.jl
using ColsD, GridLib
println("delegate loaded with its trigger: twice(GridRep) = ", twice(GridRep(rand(2, 3))))
println("loading OtherD triggers ColsDBadExt:")
using OtherD
println("ColT for GridRep2 implemented? ", ColsD.TraitWorld.witness(ColT, GridRep2) !== nothing)
