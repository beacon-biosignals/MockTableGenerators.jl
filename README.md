# MockTableGenerators.jl

[![CI](https://github.com/beacon-biosignals/MockTableGenerators.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/beacon-biosignals/MockTableGenerators.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/beacon-biosignals/MockTableGenerators.jl/branch/main/graph/badge.svg?token=sl0ZTIrtyW)](https://codecov.io/gh/beacon-biosignals/MockTableGenerators.jl)
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://beacon-biosignals.github.io/MockTableGenerators.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://beacon-biosignals.github.io/MockTableGenerators.jl/dev)

The MockTableGenerators.jl package provides an interface for composing the the generation of multiple dependent [Tables.jl](https://github.com/JuliaData/Tables.jl) to produce realistic mock datasets.

Users should define subtypes of `TableGenerator` and extend the `table_key`, `num_rows`, and `emit!` functions. Special row generators may also need to make use of `visit!` for introducing state or `dependency_key` for multiple `TableGenerator` types which creating rows for the same table. Instances of `TableGenerator`s can be constructed into a DAG which defines dependences between generators.

An example showing row generation including the use of variable number of rows, state, and conditional dependencies:

```julia
using MockTableGenerators, Dates, UUIDs

const FIRST_NAMES = ["Alice", "Bob", "Carol", "David"]
const LAST_NAMES = ["Smith", "Johnson", "Williams", "Brown"]

struct PersonGenerator <: TableGenerator
    num::AbstractRange{Int}
end

PersonGenerator(num::Integer) = PersonGenerator(range(num))

MockTableGenerators.table_key(g::PersonGenerator) = :person
MockTableGenerators.num_rows(g::PersonGenerator) = rand(g.num)

function MockTableGenerators.emit!(g::PersonGenerator, deps)
    return (; id=uuid4(), first_name=rand(FIRST_NAMES), last_name=rand(LAST_NAMES))
end


struct VisitGenerator <: TableGenerator
    num::AbstractRange{Int}
end

function MockTableGenerators.visit!(g::VisitGenerator, deps)
    n = rand(g.num)
    visits = sort!(rand(Date(1970):Day(1):Date(2000), n))
    return Dict(:i => 1, :visits => visits, :n => n)
end

MockTableGenerators.table_key(g::VisitGenerator) = :visit
MockTableGenerators.num_rows(g::VisitGenerator, state) = state[:n]

function MockTableGenerators.emit!(g::VisitGenerator, deps, state)
    visit = popfirst!(state[:visits])

    row = (; id=uuid4(), person_id=deps[:person].id, index=state[:i], date=visit)

    state[:i] += 1
    return row
end


const LIGHT_SYMPTOMS = ["Fever", "Chills", "Fatigue", "Runny nose", "Cough"]
const SEVERE_SYMPTOMS = ["Weakness", "Muscle Loss", "Fainting"]

struct SymptomGenerator <: TableGenerator
    num::AbstractRange{Int}
end

function MockTableGenerators.visit!(g::SymptomGenerator, deps)
    # Number of symptoms increase, on average, with number of visits
    n = rand(min(deps[:visit].index, last(g.num)):last(g.num))
    return (; n)
end

MockTableGenerators.table_key(g::SymptomGenerator) = :symptom
MockTableGenerators.num_rows(g::SymptomGenerator, state) = state.n

function MockTableGenerators.emit!(g::SymptomGenerator, deps, state)
    # Conditional generation based upon number of visits
    symptoms = deps[:visit].index > 2 ? SEVERE_SYMPTOMS : LIGHT_SYMPTOMS
    return (; visit_id=deps[:visit].id, symptom=rand(symptoms))
end

const DAG = [PersonGenerator(3:5) => [VisitGenerator(1:4) => [SymptomGenerator(1:2)]]]
collect(MockTableGenerators.generate(DAG))
```
