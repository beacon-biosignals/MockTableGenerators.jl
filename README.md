# MockTableGenerators.jl

[![CI](https://github.com/beacon-biosignals/MockTableGenerators.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/beacon-biosignals/MockTableGenerators.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/beacon-biosignals/MockTableGenerators.jl/branch/main/graph/badge.svg?token=sl0ZTIrtyW)](https://codecov.io/gh/beacon-biosignals/MockTableGenerators.jl)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://beacon-biosignals.github.io/MockTableGenerators.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://beacon-biosignals.github.io/MockTableGenerators.jl/dev)

The MockTableGenerators.jl package provides an interface for composing the the generation of multiple dependent [Tables.jl](https://github.com/JuliaData/Tables.jl) to produce realistic mock datasets.

Users should define subtypes of `TableGenerator` and extend the `table_key`, `num_rows`, and `emit!` functions. Special row generators may also need to make use of `visit!` for introducing state or `dependency_key` for multiple `TableGenerator` types which creating rows for the same table. Instances of `TableGenerator`s can be constructed into a DAG which defines dependences between generators.

Methods for functions that may introduce randomness (i.e., `num_rows`, `emit!`, and `visit!`) must accept a random number generator as the first argument in order to support reproducible generation.  In cases where `visit!` introduces randomness in the generated state and `emit!` and `num_rows` only consume this state, they still have to accept it but may ignore it.

An example showing row generation including the use of variable number of rows, state, and conditional dependencies:

```julia
using MockTableGenerators, Dates, StableRNGs, UUIDs

const FIRST_NAMES = ["Alice", "Bob", "Carol", "David"]
const LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown"]

struct PersonGenerator <: TableGenerator
    num::AbstractRange{Int}
end

PersonGenerator(num::Integer) = PersonGenerator(range(num))

MockTableGenerators.table_key(g::PersonGenerator) = :person
MockTableGenerators.num_rows(rng, g::PersonGenerator) = rand(rng, g.num)

function MockTableGenerators.emit!(rng, g::PersonGenerator, deps)
    return (; id=uuid4(rng), 
            first_name=rand(rng, FIRST_NAMES), 
            last_name=rand(rng, LAST_NAMES))
end


struct VisitGenerator <: TableGenerator
    num::AbstractRange{Int}
end

function MockTableGenerators.visit!(rng, g::VisitGenerator, deps)
    n = rand(rng, g.num)
    visits = sort!(rand(rng, Date(1970):Day(1):Date(2000), n))
    return Dict(:i => 1, :visits => visits, :n => n)
end

MockTableGenerators.table_key(g::VisitGenerator) = :visit
MockTableGenerators.num_rows(rng, g::VisitGenerator, state) = state[:n]

function MockTableGenerators.emit!(rng, g::VisitGenerator, deps, state)
    visit = popfirst!(state[:visits])

    row = (; id=uuid4(rng), person_id=deps[:person].id, index=state[:i], date=visit)

    state[:i] += 1
    return row
end


const LIGHT_SYMPTOMS = ["Fever", "Chills", "Fatigue", "Runny nose", "Cough"]
const SEVERE_SYMPTOMS = ["Weakness", "Muscle Loss", "Fainting"]

struct SymptomGenerator <: TableGenerator
    num::AbstractRange{Int}
end

function MockTableGenerators.visit!(rng, g::SymptomGenerator, deps)
    # Number of symptoms increase, on average, with number of visits
    n = rand(rng, min(deps[:visit].index, last(g.num)):last(g.num))
    return (; n)
end

MockTableGenerators.table_key(g::SymptomGenerator) = :symptom
MockTableGenerators.num_rows(rng, g::SymptomGenerator, state) = state.n

function MockTableGenerators.emit!(rng, g::SymptomGenerator, deps, state)
    # Conditional generation based upon number of visits
    symptoms = deps[:visit].index > 2 ? SEVERE_SYMPTOMS : LIGHT_SYMPTOMS
    return (; visit_id=deps[:visit].id, symptom=rand(rng, symptoms))
end

const DAG = [PersonGenerator(3:5) => [VisitGenerator(1:4) => [SymptomGenerator(1:2)]]]
# pass RNG for reproducible generation:
results = collect(MockTableGenerators.generate(StableRNG(11), DAG))

# Alternatively, since v0.2.1, linear DAGs can be also constructed in a flat representation:
const FLAT_DAG = PersonGenerator(3:5) => VisitGenerator(1:4) => SymptomGenerator(1:2)
flat_results = collect(MockTableGenerators.generate(StableRNG(11), FLAT_DAG))

@assert results == flat_results
```
