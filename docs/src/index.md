```@meta
CurrentModule = MockTableGenerators
```

# MockTableGenerators.jl

This package provides an interface for composing the the generation of multiple dependent
[Tables.jl](https://github.com/JuliaData/Tables.jl)-compatible tables to produce realistic
mock datasets.

The interface is based around a `TableGenerator` abstract type and a set of associated
methods that describe various properties of the tables and the relationships between them.
Generators, i.e. instances of subtypes of `TableGenerator`, can then be organized into a
[directed acyclic graph](https://en.wikipedia.org/wiki/Directed_acyclic_graph) (DAG) that
defines the dependencies between generators.

Defining a generator is as simple as defining a subtype of `TableGenerator` and extending
the functions [`table_key`](@ref), [`num_rows`](@ref), and [`emit!`](@ref).
Special row generators may also need to extend [`visit!`](@ref) for introducing state or
[`dependency_key`](@ref) for multiple `TableGenerator` types which creating rows for the
same table.

## API

```@docs
table_key
num_rows
emit!
dependency_key
visit!
```

## Example

Say we want to define tables `person`, `visit`, and `symptom`, the rows of which describe
people, their visits to a doctor's office, and the symptoms with which they presented at
each visit, respectively.

We'll start by describing the people.
Each person will have a first name and last name and will be uniquely identified by
a UUID.

```julia
using MockTableGenerators, Dates, UUIDs

first_names = ["Alice", "Bob", "Carol", "David"]
last_names = ["Smith", "Johnson", "Williams", "Brown"]

# We'll use the `num` field here to provide bounds on the number of generated rows
struct PersonGenerator <: TableGenerator
    num::UnitRange{Int}
end

# Rows of this table will be associated with the name `person` in the generated output
MockTableGenerators.table_key(g::PersonGenerator) = :person

# There will be a random number of rows within the bounds set by the generator type
MockTableGenerators.num_rows(g::PersonGenerator) = rand(g.num)

# Each row will have a `UUID` called `id` and a random pairing of first and last names
function MockTableGenerators.emit!(g::PersonGenerator, deps)
    return (; id=uuid4(), first_name=rand(first_names), last_name=rand(last_names))
end
```

With that setup, let's try generating just a table of exactly four people, ignoring
visits and symptoms for now.
To use the generator to generate tables, we'll simply pass it to `generate`.

```julia-repl
julia> MockTableGenerators.generate(PersonGenerator(4:4))
Channel{Any}(10) (closed)

julia> collect(ans)
4-element Vector{Any}:
 :person => (id = UUID("16834dca-ae91-4781-a930-6323d2a57b03"), first_name = "Carol", last_name = "Brown")
 :person => (id = UUID("71e93c3e-561c-4bc7-896f-a0b1672ef743"), first_name = "Carol", last_name = "Smith")
 :person => (id = UUID("70d68ba0-a82a-4ccb-9967-09b2da69b3af"), first_name = "David", last_name = "Brown")
 :person => (id = UUID("b3090234-3d62-4bdd-b976-a93bb8d129b4"), first_name = "Bob", last_name = "Johnson")
```

The output of `generate` is a `Channel` that iterates `table_key => row` pairs.

Now let's add visits to the mix:

```julia
struct VisitGenerator <: TableGenerator
    num::UnitRange{Int}
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
```

And symptoms:

```julia
light_symptoms = ["Fever", "Chills", "Fatigue", "Runny nose", "Cough"]
severe_symptoms = ["Weakness", "Muscle Loss", "Fainting"]

struct SymptomGenerator <: TableGenerator
    num::UnitRange{Int}
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
    symptoms = deps[:visit].index > 2 ? severe_symptoms : light_symptoms
    return (; visit_id=deps[:visit].id, symptom=rand(symptoms))
end
```

In this case, our DAG looks like a straight shot from persons to visits to symptoms.
We'll generate rows for 3 to 5 people, each with 1 to 4 visits, at which they had 1 or 2
symptoms.

```julia-repl
julia> dag = [PersonGenerator(3:5) => [VisitGenerator(1:4) => [SymptomGenerator(1:2)]]];

julia> results = collect(MockTableGenerators.generate(dag))
29-element Vector{Any}:
  :person => (id = UUID("f243cfbd-7ba0-4d65-aac3-60d02d8395d6"), first_name = "Bob", last_name = "Brown")
   :visit => (id = UUID("9760d38f-0749-40f4-973d-b8818f317ed2"), person_id = UUID("f243cfbd-7ba0-4d65-aac3-60d02d8395d6"), index = 1, date = Date("1972-07-17"))
 :symptom => (visit_id = UUID("9760d38f-0749-40f4-973d-b8818f317ed2"), symptom = "Runny nose")
   :visit => (id = UUID("4855b672-64be-468b-b3a1-dd7a595c180b"), person_id = UUID("f243cfbd-7ba0-4d65-aac3-60d02d8395d6"), index = 2, date = Date("1982-10-29"))
 :symptom => (visit_id = UUID("4855b672-64be-468b-b3a1-dd7a595c180b"), symptom = "Cough")
 :symptom => (visit_id = UUID("4855b672-64be-468b-b3a1-dd7a595c180b"), symptom = "Runny nose")
   :visit => (id = UUID("a3be2559-9670-438c-ae30-a7c1f4698baa"), person_id = UUID("f243cfbd-7ba0-4d65-aac3-60d02d8395d6"), index = 3, date = Date("1983-12-30"))
 :symptom => (visit_id = UUID("a3be2559-9670-438c-ae30-a7c1f4698baa"), symptom = "Muscle Loss")
 :symptom => (visit_id = UUID("a3be2559-9670-438c-ae30-a7c1f4698baa"), symptom = "Muscle Loss")
   :visit => (id = UUID("1b20aa89-22c8-4c71-84c4-5a95267fb5ba"), person_id = UUID("f243cfbd-7ba0-4d65-aac3-60d02d8395d6"), index = 4, date = Date("1995-04-30"))
 :symptom => (visit_id = UUID("1b20aa89-22c8-4c71-84c4-5a95267fb5ba"), symptom = "Muscle Loss")
 :symptom => (visit_id = UUID("1b20aa89-22c8-4c71-84c4-5a95267fb5ba"), symptom = "Fainting")
  :person => (id = UUID("109b935e-70fd-42b9-a623-aeefc3557b6e"), first_name = "Alice", last_name = "Williams")
   :visit => (id = UUID("7366ea7e-f6f5-41c9-8c48-4e0b060cd7af"), person_id = UUID("109b935e-70fd-42b9-a623-aeefc3557b6e"), index = 1, date = Date("1972-02-10"))
 :symptom => (visit_id = UUID("7366ea7e-f6f5-41c9-8c48-4e0b060cd7af"), symptom = "Fever")
 :symptom => (visit_id = UUID("7366ea7e-f6f5-41c9-8c48-4e0b060cd7af"), symptom = "Fever")
   :visit => (id = UUID("41f0d3df-1ad7-4906-8995-49e4387631d5"), person_id = UUID("109b935e-70fd-42b9-a623-aeefc3557b6e"), index = 2, date = Date("1982-04-07"))
 :symptom => (visit_id = UUID("41f0d3df-1ad7-4906-8995-49e4387631d5"), symptom = "Runny nose")
 :symptom => (visit_id = UUID("41f0d3df-1ad7-4906-8995-49e4387631d5"), symptom = "Chills")
  :person => (id = UUID("598c059f-4138-41f5-8350-6c47cc4351aa"), first_name = "Bob", last_name = "Johnson")
   :visit => (id = UUID("033dd1c4-8700-4d27-91e9-05e2d2aa541e"), person_id = UUID("598c059f-4138-41f5-8350-6c47cc4351aa"), index = 1, date = Date("1983-06-09"))
 :symptom => (visit_id = UUID("033dd1c4-8700-4d27-91e9-05e2d2aa541e"), symptom = "Chills")
   :visit => (id = UUID("69b6b83c-1825-49c6-ae26-c902dc01f121"), person_id = UUID("598c059f-4138-41f5-8350-6c47cc4351aa"), index = 2, date = Date("1986-09-30"))
 :symptom => (visit_id = UUID("69b6b83c-1825-49c6-ae26-c902dc01f121"), symptom = "Chills")
 :symptom => (visit_id = UUID("69b6b83c-1825-49c6-ae26-c902dc01f121"), symptom = "Fever")
  :person => (id = UUID("3f79f2fa-5830-41b1-8a8f-47b2d76b21bb"), first_name = "Carol", last_name = "Smith")
   :visit => (id = UUID("5198d75c-8e1c-4d93-8ae9-ab976c4484ff"), person_id = UUID("3f79f2fa-5830-41b1-8a8f-47b2d76b21bb"), index = 1, date = Date("1977-07-21"))
 :symptom => (visit_id = UUID("5198d75c-8e1c-4d93-8ae9-ab976c4484ff"), symptom = "Fatigue")
 :symptom => (visit_id = UUID("5198d75c-8e1c-4d93-8ae9-ab976c4484ff"), symptom = "Fatigue")
```

We can also separate these into individual tables.
One, but not the only, way to do this is as follows.

```julia-repl
julia> using DataFrames

julia> tables = Dict{Symbol,DataFrame}();

julia> for (name, row) in results
           push!(get!(tables, name, DataFrame()), row)
       end

julia> tables[:person]
4×3 DataFrame
 Row │ id                                 first_name  last_name
     │ UUID                               String      String
─────┼──────────────────────────────────────────────────────────
   1 │ f243cfbd-7ba0-4d65-aac3-60d02d83…  Bob         Brown
   2 │ 109b935e-70fd-42b9-a623-aeefc355…  Alice       Williams
   3 │ 598c059f-4138-41f5-8350-6c47cc43…  Bob         Johnson
   4 │ 3f79f2fa-5830-41b1-8a8f-47b2d76b…  Carol       Smith

julia> tables[:visit]
9×4 DataFrame
 Row │ id                                 person_id                          index  date
     │ UUID                               UUID                               Int64  Date
─────┼─────────────────────────────────────────────────────────────────────────────────────────
   1 │ 9760d38f-0749-40f4-973d-b8818f31…  f243cfbd-7ba0-4d65-aac3-60d02d83…      1  1972-07-17
   2 │ 4855b672-64be-468b-b3a1-dd7a595c…  f243cfbd-7ba0-4d65-aac3-60d02d83…      2  1982-10-29
   3 │ a3be2559-9670-438c-ae30-a7c1f469…  f243cfbd-7ba0-4d65-aac3-60d02d83…      3  1983-12-30
   4 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  f243cfbd-7ba0-4d65-aac3-60d02d83…      4  1995-04-30
   5 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  109b935e-70fd-42b9-a623-aeefc355…      1  1972-02-10
   6 │ 41f0d3df-1ad7-4906-8995-49e43876…  109b935e-70fd-42b9-a623-aeefc355…      2  1982-04-07
   7 │ 033dd1c4-8700-4d27-91e9-05e2d2aa…  598c059f-4138-41f5-8350-6c47cc43…      1  1983-06-09
   8 │ 69b6b83c-1825-49c6-ae26-c902dc01…  598c059f-4138-41f5-8350-6c47cc43…      2  1986-09-30
   9 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  3f79f2fa-5830-41b1-8a8f-47b2d76b…      1  1977-07-21

julia> tables[:visit]
16×2 DataFrame
 Row │ visit_id                           symptom
     │ UUID                               String
─────┼────────────────────────────────────────────────
   1 │ 9760d38f-0749-40f4-973d-b8818f31…  Runny nose
   2 │ 4855b672-64be-468b-b3a1-dd7a595c…  Cough
   3 │ 4855b672-64be-468b-b3a1-dd7a595c…  Runny nose
   4 │ a3be2559-9670-438c-ae30-a7c1f469…  Muscle Loss
   5 │ a3be2559-9670-438c-ae30-a7c1f469…  Muscle Loss
   6 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  Muscle Loss
   7 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  Fainting
   8 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  Fever
   9 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  Fever
  10 │ 41f0d3df-1ad7-4906-8995-49e43876…  Runny nose
  11 │ 41f0d3df-1ad7-4906-8995-49e43876…  Chills
  12 │ 033dd1c4-8700-4d27-91e9-05e2d2aa…  Chills
  13 │ 69b6b83c-1825-49c6-ae26-c902dc01…  Chills
  14 │ 69b6b83c-1825-49c6-ae26-c902dc01…  Fever
  15 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  Fatigue
  16 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  Fatigue
```
