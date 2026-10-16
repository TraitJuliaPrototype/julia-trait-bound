# Where unreadable errors come from (session 22)

Measured error messages for design-findings §17. Nothing here belongs to the PoC.

C++ (GCC 14.2):

    g++ -std=c++17 -c sort_list.cpp -o /dev/null           # std::sort on a std::list
    g++ -std=c++20 -c sort_list_concepts.cpp -o /dev/null  # std::ranges::sort on a std::list (concepts)
    g++ -std=c++17 -c nested.cpp -o /dev/null              # std::sort of vector<pair<string, Point>>, Point without <

Julia 1.12.2 with OrdinaryDiffEq from the default environment (writes the
messages, as the REPL prints them and in full, next to the scripts):

    julia +1.12.2 --startup-file=no --project=@v1.12 sciml_errors.jl           # missing parameters; Float64 cache under ForwardDiff.gradient
    julia +1.12.2 --startup-file=no --project=@v1.12 sciml_errors_implicit.jl  # the same cache under Rodas5's automatic Jacobian

| case | lines | bytes (REPL / full) | frames | longest line |
|---|---|---|---|---|
| C++ `std::sort` on `std::list` | 28 | 2,704 | 1 instantiation step | — |
| C++ `std::ranges::sort` on `std::list` (concepts) | 29 | 3,367 | — | — |
| C++ `std::sort`, `Point` without `<` | 33 | 3,938 | 6 instantiation steps | — |
| SciML, parameters never passed | 71 | 5,602 / 10,583 | 29 | 3,789 |
| SciML, `Float64` cache under `ForwardDiff.gradient` | 101 | 6,559 / 13,811 | 44 | 5,574 |
| SciML, the same cache under `Rodas5()` | 81 | 4,704 / 89,627 | 22 | 33,673 |

`typeof(integrator)` for `Tsit5` on a 3-vector: 3,553 characters, 75 type-parameter lists.
