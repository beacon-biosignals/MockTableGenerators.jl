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
using MockTableGenerators, Dates, StableRNGs, UUIDs

first_names = ["Alice", "Bob", "Carol", "David"]
last_names = ["Smith", "Johnson", "Williams", "Brown"]

# We'll use the `num` field here to provide bounds on the number of generated rows
struct PersonGenerator <: TableGenerator
    num::UnitRange{Int}
end

# Rows of this table will be associated with the name `person` in the generated output
MockTableGenerators.table_key(g::PersonGenerator) = :person

# There will be a random number of rows within the bounds set by the generator type
MockTableGenerators.num_rows(rng, g::PersonGenerator) = rand(rng, g.num)

# Each row will have a `UUID` called `id` and a random pairing of first and last names
function MockTableGenerators.emit!(rng, g::PersonGenerator, deps)
    return (; id=uuid4(rng),
            first_name=rand(rng, first_names),
            last_name=rand(rng, last_names))
end
```

With that setup, let's try generating just a table of exactly four people, ignoring
visits and symptoms for now.
To use the generator to generate rows, we'll simply pass it to `generate`.
In this example, we'll use a `StableRNG` from the StableRNGs.jl package to reproducibly
generate the rows.
Note that providing a random number generator when calling `generate` is optional, but
new methods like those shown above must allow one to be passed as the first argument.

```julia-repl
julia> rng = StableRNG(11);

julia> MockTableGenerators.generate(rng, PersonGenerator(4:4))
Channel{Any}(10) (closed)

julia> collect(ans)
4-element Vector{Any}:
 :person => (id = UUID("5a3d3d5e-ff13-417a-8b79-7c9e0c9cfb56"), first_name = "David", last_name = "Brown")
 :person => (id = UUID("9231b8a2-2320-4ef4-a1ed-0719b3373395"), first_name = "Bob", last_name = "Williams")
 :person => (id = UUID("80f3c3fb-afb7-44de-889d-0b95221178c2"), first_name = "Bob", last_name = "Brown")
 :person => (id = UUID("19829759-e683-4d01-8481-cba1b28467d7"), first_name = "Alice", last_name = "Brown")
```

The output of `generate` is a `Channel` that iterates `table_key => row` pairs.

Now let's add visits to the mix:

```julia
struct VisitGenerator <: TableGenerator
    num::UnitRange{Int}
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
```

And symptoms:

```julia
light_symptoms = ["Fever", "Chills", "Fatigue", "Runny nose", "Cough"]
severe_symptoms = ["Weakness", "Muscle Loss", "Fainting"]

struct SymptomGenerator <: TableGenerator
    num::UnitRange{Int}
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
    symptoms = deps[:visit].index > 2 ? severe_symptoms : light_symptoms
    return (; visit_id=deps[:visit].id, symptom=rand(rng, symptoms))
end
```

In this case, our DAG looks like a straight shot from persons to visits to symptoms.
We'll generate rows for 3 to 5 people, each with 1 to 4 visits, at which they had 1 or 2
symptoms.

```julia-repl
julia> dag = [PersonGenerator(3:5) => [VisitGenerator(1:4) => [SymptomGenerator(1:2)]]];

julia> results = collect(MockTableGenerators.generate(dag))
45-element Vector{Any}:
  :person => (id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), first_name = "Bob", last_name = "Williams")
   :visit => (id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 1, date = Date("1974-06-02"))
 :symptom => (visit_id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), symptom = "Fever")
 :symptom => (visit_id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), symptom = "Runny nose")
   :visit => (id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 2, date = Date("1982-08-04"))
 :symptom => (visit_id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), symptom = "Fatigue")
 :symptom => (visit_id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), symptom = "Chills")
   :visit => (id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 3, date = Date("1985-01-10"))
 :symptom => (visit_id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), symptom = "Muscle Loss")
 :symptom => (visit_id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), symptom = "Weakness")
   :visit => (id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 4, date = Date("1994-10-02"))
 :symptom => (visit_id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), symptom = "Fainting")
 :symptom => (visit_id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), symptom = "Muscle Loss")
  :person => (id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), first_name = "Bob", last_name = "Brown")
   :visit => (id = UUID("443b40e3-a6a2-40bc-8f66-71f5c22da685"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 1, date = Date("1972-06-30"))
 :symptom => (visit_id = UUID("443b40e3-a6a2-40bc-8f66-71f5c22da685"), symptom = "Fatigue")
   :visit => (id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 2, date = Date("1989-04-23"))
 :symptom => (visit_id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), symptom = "Fatigue")
 :symptom => (visit_id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), symptom = "Chills")
   :visit => (id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 3, date = Date("1991-09-07"))
 :symptom => (visit_id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), symptom = "Muscle Loss")
 :symptom => (visit_id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), symptom = "Fainting")
  :person => (id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), first_name = "Bob", last_name = "Brown")
   :visit => (id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 1, date = Date("1973-09-05"))
 :symptom => (visit_id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), symptom = "Fever")
 :symptom => (visit_id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), symptom = "Fatigue")
   :visit => (id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 2, date = Date("1998-12-11"))
 :symptom => (visit_id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), symptom = "Runny nose")
 :symptom => (visit_id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), symptom = "Fever")
   :visit => (id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 3, date = Date("1999-05-10"))
 :symptom => (visit_id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), symptom = "Weakness")
 :symptom => (visit_id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), symptom = "Fainting")
  :person => (id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), first_name = "Carol", last_name = "Smith")
   :visit => (id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 1, date = Date("1973-06-13"))
 :symptom => (visit_id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), symptom = "Runny nose")
 :symptom => (visit_id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), symptom = "Runny nose")
   :visit => (id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 2, date = Date("1980-07-05"))
 :symptom => (visit_id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), symptom = "Fever")
 :symptom => (visit_id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), symptom = "Cough")
   :visit => (id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 3, date = Date("1981-02-15"))
 :symptom => (visit_id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), symptom = "Weakness")
 :symptom => (visit_id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), symptom = "Weakness")
   :visit => (id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 4, date = Date("1998-03-24"))
 :symptom => (visit_id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), symptom = "Fainting")
 :symptom => (visit_id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), symptom = "Muscle Loss")
```

We can also separate these into individual tables. This can be done after generating rows
by calling `collect_tables`, or tables can be generated directly using `generate_tables` in
place of `generate`. The following example shows the former to organize the rows generated
above.

```julia-repl
julia> tables = MockTableGenerators.collect_tables(results);

julia> tables.person
4-element Vector{@NamedTuple{id::UUID, first_name::String, last_name::String}}:
 (id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), first_name = "Bob", last_name = "Williams")
 (id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), first_name = "Bob", last_name = "Brown")
 (id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), first_name = "Bob", last_name = "Brown")
 (id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), first_name = "Carol", last_name = "Smith")

julia> tables.visit
14-element Vector{@NamedTuple{id::UUID, person_id::UUID, index::Int64, date::Date}}:
 (id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 1, date = Date("1974-06-02"))
 (id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 2, date = Date("1982-08-04"))
 (id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 3, date = Date("1985-01-10"))
 (id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), person_id = UUID("34cdf816-7ac5-4e9d-8ef1-1957242d4496"), index = 4, date = Date("1994-10-02"))
 (id = UUID("443b40e3-a6a2-40bc-8f66-71f5c22da685"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 1, date = Date("1972-06-30"))
 (id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 2, date = Date("1989-04-23"))
 (id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), person_id = UUID("1dbe6a94-f238-481c-8137-c5a06272c93f"), index = 3, date = Date("1991-09-07"))
 (id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 1, date = Date("1973-09-05"))
 (id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 2, date = Date("1998-12-11"))
 (id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), person_id = UUID("8bdfb2a4-d99b-4a77-85e4-1e1ce3461aaa"), index = 3, date = Date("1999-05-10"))
 (id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 1, date = Date("1973-06-13"))
 (id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 2, date = Date("1980-07-05"))
 (id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 3, date = Date("1981-02-15"))
 (id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), person_id = UUID("4c372d3e-1b44-4818-84d7-1268a624d4aa"), index = 4, date = Date("1998-03-24"))

julia> tables.symptom
27-element Vector{@NamedTuple{visit_id::UUID, symptom::String}}:
 (visit_id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), symptom = "Fever")
 (visit_id = UUID("cea4339d-325a-41f8-9a5e-fd02323591ba"), symptom = "Runny nose")
 (visit_id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), symptom = "Fatigue")
 (visit_id = UUID("d54d21b0-59d0-4595-882f-c7bc0fc7bde4"), symptom = "Chills")
 (visit_id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), symptom = "Muscle Loss")
 (visit_id = UUID("77139cf8-6bdc-43a1-96dd-be3f8d850b30"), symptom = "Weakness")
 (visit_id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), symptom = "Fainting")
 (visit_id = UUID("c707dbd5-519a-4948-bdb2-57225970ef9a"), symptom = "Muscle Loss")
 (visit_id = UUID("443b40e3-a6a2-40bc-8f66-71f5c22da685"), symptom = "Fatigue")
 (visit_id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), symptom = "Fatigue")
 (visit_id = UUID("cae1ad18-40b5-4eec-91ec-52b65d8c346f"), symptom = "Chills")
 (visit_id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), symptom = "Muscle Loss")
 (visit_id = UUID("11d23dc3-63c5-48d2-890d-2623d5a48261"), symptom = "Fainting")
 (visit_id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), symptom = "Fever")
 (visit_id = UUID("98a05704-62fa-4a30-b41b-95a765c963af"), symptom = "Fatigue")
 (visit_id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), symptom = "Runny nose")
 (visit_id = UUID("d05f883e-68f7-46fc-a106-042f10749bf3"), symptom = "Fever")
 (visit_id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), symptom = "Weakness")
 (visit_id = UUID("fc6a14a5-49f3-4746-b22d-f451e1dc4507"), symptom = "Fainting")
 (visit_id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), symptom = "Runny nose")
 (visit_id = UUID("e9dc403e-443b-4b15-8894-fc399967b1e5"), symptom = "Runny nose")
 (visit_id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), symptom = "Fever")
 (visit_id = UUID("84cd20d4-8836-464f-a76c-52ec80b9c022"), symptom = "Cough")
 (visit_id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), symptom = "Weakness")
 (visit_id = UUID("49ad303b-db4a-4000-9376-c11580e22d4a"), symptom = "Weakness")
 (visit_id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), symptom = "Fainting")
 (visit_id = UUID("6e3a09c8-8cbd-4dd5-82ef-ba1d54c43e11"), symptom = "Muscle Loss")
```

Each of the tables created via `collect_tables` (or `generate_tables`) is compliant with
the Tables.jl interface and, in Tables.jl parlance, is a "row table," i.e. an iterable
collection of rows with a common schema.
