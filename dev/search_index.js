var documenterSearchIndex = {"docs":
[{"location":"","page":"API Documentation","title":"API Documentation","text":"CurrentModule = MockTableGenerators","category":"page"},{"location":"#MockTableGenerators.jl","page":"API Documentation","title":"MockTableGenerators.jl","text":"","category":"section"},{"location":"","page":"API Documentation","title":"API Documentation","text":"This package provides an interface for composing the the generation of multiple dependent Tables.jl-compatible tables to produce realistic mock datasets.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"The interface is based around a TableGenerator abstract type and a set of associated methods that describe various properties of the tables and the relationships between them. Generators, i.e. instances of subtypes of TableGenerator, can then be organized into a directed acyclic graph (DAG) that defines the dependencies between generators.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"Defining a generator is as simple as defining a subtype of TableGenerator and extending the functions table_key, num_rows, and emit!. Special row generators may also need to extend visit! for introducing state or dependency_key for multiple TableGenerator types which creating rows for the same table.","category":"page"},{"location":"#API","page":"API Documentation","title":"API","text":"","category":"section"},{"location":"","page":"API Documentation","title":"API Documentation","text":"table_key\nnum_rows\nemit!\ndependency_key\nvisit!","category":"page"},{"location":"#MockTableGenerators.table_key","page":"API Documentation","title":"MockTableGenerators.table_key","text":"table_key(::TableGenerator) -> Symbol\n\nStates the name of the table associated with the subtype instance of TableGenerator. The defined name will be included in the DAG output to identify the row's table.\n\n\n\n\n\n","category":"function"},{"location":"#MockTableGenerators.num_rows","page":"API Documentation","title":"MockTableGenerators.num_rows","text":"num_rows(rng::AbstractRNG, g::TableGenerator, state=nothing) -> Int\nnum_rows(rng::AbstractRNG, g::TableGenerator) -> Int\n\nReturns the number of rows that should be produced for this DAG node visit. The number of rows can vary between DAG visits.\n\n\n\n\n\n","category":"function"},{"location":"#MockTableGenerators.emit!","page":"API Documentation","title":"MockTableGenerators.emit!","text":"emit(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any}, state=nothing)\nemit(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any})\n\nProduces a single row from the table generator. Dependent generators will be passed the contents of the rows they depend on via deps and indexed by the result of dependency_key. Any state returned from visit!(g, ...) will be passed into this function via state allowing row generation to be conditional on previous rows created by this generator.\n\n\n\n\n\n","category":"function"},{"location":"#MockTableGenerators.dependency_key","page":"API Documentation","title":"MockTableGenerators.dependency_key","text":"dependency_key(::TableGenerator) -> Symbol\n\nStates the key used in the dependency dictionary (deps) to uniquely identify this TableGenerator. When undefined dependency_key will fall back on calling table_key.\n\nSee also: emit!, table_key\n\n\n\n\n\n","category":"function"},{"location":"#MockTableGenerators.visit!","page":"API Documentation","title":"MockTableGenerators.visit!","text":"visit!(rng, g::TableGenerator, deps)\n\nFunction allows generates to update state each time the node is visited the the DAG. When a TableGenerator creates a batch of rows this function is only called once.\n\n\n\n\n\n","category":"function"},{"location":"#Example","page":"API Documentation","title":"Example","text":"","category":"section"},{"location":"","page":"API Documentation","title":"API Documentation","text":"Say we want to define tables person, visit, and symptom, the rows of which describe people, their visits to a doctor's office, and the symptoms with which they presented at each visit, respectively.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"We'll start by describing the people. Each person will have a first name and last name and will be uniquely identified by a UUID.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"using MockTableGenerators, Dates, UUIDs\n\nfirst_names = [\"Alice\", \"Bob\", \"Carol\", \"David\"]\nlast_names = [\"Smith\", \"Johnson\", \"Williams\", \"Brown\"]\n\n# We'll use the `num` field here to provide bounds on the number of generated rows\nstruct PersonGenerator <: TableGenerator\n    num::UnitRange{Int}\nend\n\n# Rows of this table will be associated with the name `person` in the generated output\nMockTableGenerators.table_key(g::PersonGenerator) = :person\n\n# There will be a random number of rows within the bounds set by the generator type\nMockTableGenerators.num_rows(g::PersonGenerator) = rand(g.num)\n\n# Each row will have a `UUID` called `id` and a random pairing of first and last names\nfunction MockTableGenerators.emit!(g::PersonGenerator, deps)\n    return (; id=uuid4(), first_name=rand(first_names), last_name=rand(last_names))\nend","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"With that setup, let's try generating just a table of exactly four people, ignoring visits and symptoms for now. To use the generator to generate tables, we'll simply pass it to generate.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"julia> MockTableGenerators.generate(PersonGenerator(4:4))\nChannel{Any}(10) (closed)\n\njulia> collect(ans)\n4-element Vector{Any}:\n :person => (id = UUID(\"16834dca-ae91-4781-a930-6323d2a57b03\"), first_name = \"Carol\", last_name = \"Brown\")\n :person => (id = UUID(\"71e93c3e-561c-4bc7-896f-a0b1672ef743\"), first_name = \"Carol\", last_name = \"Smith\")\n :person => (id = UUID(\"70d68ba0-a82a-4ccb-9967-09b2da69b3af\"), first_name = \"David\", last_name = \"Brown\")\n :person => (id = UUID(\"b3090234-3d62-4bdd-b976-a93bb8d129b4\"), first_name = \"Bob\", last_name = \"Johnson\")","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"The output of generate is a Channel that iterates table_key => row pairs.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"Now let's add visits to the mix:","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"struct VisitGenerator <: TableGenerator\n    num::UnitRange{Int}\nend\n\nfunction MockTableGenerators.visit!(g::VisitGenerator, deps)\n    n = rand(g.num)\n    visits = sort!(rand(Date(1970):Day(1):Date(2000), n))\n    return Dict(:i => 1, :visits => visits, :n => n)\nend\n\nMockTableGenerators.table_key(g::VisitGenerator) = :visit\n\nMockTableGenerators.num_rows(g::VisitGenerator, state) = state[:n]\n\nfunction MockTableGenerators.emit!(g::VisitGenerator, deps, state)\n    visit = popfirst!(state[:visits])\n    row = (; id=uuid4(), person_id=deps[:person].id, index=state[:i], date=visit)\n    state[:i] += 1\n    return row\nend","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"And symptoms:","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"light_symptoms = [\"Fever\", \"Chills\", \"Fatigue\", \"Runny nose\", \"Cough\"]\nsevere_symptoms = [\"Weakness\", \"Muscle Loss\", \"Fainting\"]\n\nstruct SymptomGenerator <: TableGenerator\n    num::UnitRange{Int}\nend\n\nfunction MockTableGenerators.visit!(g::SymptomGenerator, deps)\n    # Number of symptoms increase, on average, with number of visits\n    n = rand(min(deps[:visit].index, last(g.num)):last(g.num))\n    return (; n)\nend\n\nMockTableGenerators.table_key(g::SymptomGenerator) = :symptom\nMockTableGenerators.num_rows(g::SymptomGenerator, state) = state.n\n\nfunction MockTableGenerators.emit!(g::SymptomGenerator, deps, state)\n    # Conditional generation based upon number of visits\n    symptoms = deps[:visit].index > 2 ? severe_symptoms : light_symptoms\n    return (; visit_id=deps[:visit].id, symptom=rand(symptoms))\nend","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"In this case, our DAG looks like a straight shot from persons to visits to symptoms. We'll generate rows for 3 to 5 people, each with 1 to 4 visits, at which they had 1 or 2 symptoms.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"julia> dag = [PersonGenerator(3:5) => [VisitGenerator(1:4) => [SymptomGenerator(1:2)]]];\n\njulia> results = collect(MockTableGenerators.generate(dag))\n29-element Vector{Any}:\n  :person => (id = UUID(\"f243cfbd-7ba0-4d65-aac3-60d02d8395d6\"), first_name = \"Bob\", last_name = \"Brown\")\n   :visit => (id = UUID(\"9760d38f-0749-40f4-973d-b8818f317ed2\"), person_id = UUID(\"f243cfbd-7ba0-4d65-aac3-60d02d8395d6\"), index = 1, date = Date(\"1972-07-17\"))\n :symptom => (visit_id = UUID(\"9760d38f-0749-40f4-973d-b8818f317ed2\"), symptom = \"Runny nose\")\n   :visit => (id = UUID(\"4855b672-64be-468b-b3a1-dd7a595c180b\"), person_id = UUID(\"f243cfbd-7ba0-4d65-aac3-60d02d8395d6\"), index = 2, date = Date(\"1982-10-29\"))\n :symptom => (visit_id = UUID(\"4855b672-64be-468b-b3a1-dd7a595c180b\"), symptom = \"Cough\")\n :symptom => (visit_id = UUID(\"4855b672-64be-468b-b3a1-dd7a595c180b\"), symptom = \"Runny nose\")\n   :visit => (id = UUID(\"a3be2559-9670-438c-ae30-a7c1f4698baa\"), person_id = UUID(\"f243cfbd-7ba0-4d65-aac3-60d02d8395d6\"), index = 3, date = Date(\"1983-12-30\"))\n :symptom => (visit_id = UUID(\"a3be2559-9670-438c-ae30-a7c1f4698baa\"), symptom = \"Muscle Loss\")\n :symptom => (visit_id = UUID(\"a3be2559-9670-438c-ae30-a7c1f4698baa\"), symptom = \"Muscle Loss\")\n   :visit => (id = UUID(\"1b20aa89-22c8-4c71-84c4-5a95267fb5ba\"), person_id = UUID(\"f243cfbd-7ba0-4d65-aac3-60d02d8395d6\"), index = 4, date = Date(\"1995-04-30\"))\n :symptom => (visit_id = UUID(\"1b20aa89-22c8-4c71-84c4-5a95267fb5ba\"), symptom = \"Muscle Loss\")\n :symptom => (visit_id = UUID(\"1b20aa89-22c8-4c71-84c4-5a95267fb5ba\"), symptom = \"Fainting\")\n  :person => (id = UUID(\"109b935e-70fd-42b9-a623-aeefc3557b6e\"), first_name = \"Alice\", last_name = \"Williams\")\n   :visit => (id = UUID(\"7366ea7e-f6f5-41c9-8c48-4e0b060cd7af\"), person_id = UUID(\"109b935e-70fd-42b9-a623-aeefc3557b6e\"), index = 1, date = Date(\"1972-02-10\"))\n :symptom => (visit_id = UUID(\"7366ea7e-f6f5-41c9-8c48-4e0b060cd7af\"), symptom = \"Fever\")\n :symptom => (visit_id = UUID(\"7366ea7e-f6f5-41c9-8c48-4e0b060cd7af\"), symptom = \"Fever\")\n   :visit => (id = UUID(\"41f0d3df-1ad7-4906-8995-49e4387631d5\"), person_id = UUID(\"109b935e-70fd-42b9-a623-aeefc3557b6e\"), index = 2, date = Date(\"1982-04-07\"))\n :symptom => (visit_id = UUID(\"41f0d3df-1ad7-4906-8995-49e4387631d5\"), symptom = \"Runny nose\")\n :symptom => (visit_id = UUID(\"41f0d3df-1ad7-4906-8995-49e4387631d5\"), symptom = \"Chills\")\n  :person => (id = UUID(\"598c059f-4138-41f5-8350-6c47cc4351aa\"), first_name = \"Bob\", last_name = \"Johnson\")\n   :visit => (id = UUID(\"033dd1c4-8700-4d27-91e9-05e2d2aa541e\"), person_id = UUID(\"598c059f-4138-41f5-8350-6c47cc4351aa\"), index = 1, date = Date(\"1983-06-09\"))\n :symptom => (visit_id = UUID(\"033dd1c4-8700-4d27-91e9-05e2d2aa541e\"), symptom = \"Chills\")\n   :visit => (id = UUID(\"69b6b83c-1825-49c6-ae26-c902dc01f121\"), person_id = UUID(\"598c059f-4138-41f5-8350-6c47cc4351aa\"), index = 2, date = Date(\"1986-09-30\"))\n :symptom => (visit_id = UUID(\"69b6b83c-1825-49c6-ae26-c902dc01f121\"), symptom = \"Chills\")\n :symptom => (visit_id = UUID(\"69b6b83c-1825-49c6-ae26-c902dc01f121\"), symptom = \"Fever\")\n  :person => (id = UUID(\"3f79f2fa-5830-41b1-8a8f-47b2d76b21bb\"), first_name = \"Carol\", last_name = \"Smith\")\n   :visit => (id = UUID(\"5198d75c-8e1c-4d93-8ae9-ab976c4484ff\"), person_id = UUID(\"3f79f2fa-5830-41b1-8a8f-47b2d76b21bb\"), index = 1, date = Date(\"1977-07-21\"))\n :symptom => (visit_id = UUID(\"5198d75c-8e1c-4d93-8ae9-ab976c4484ff\"), symptom = \"Fatigue\")\n :symptom => (visit_id = UUID(\"5198d75c-8e1c-4d93-8ae9-ab976c4484ff\"), symptom = \"Fatigue\")","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"We can also separate these into individual tables. One, but not the only, way to do this is as follows.","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"julia> using DataFrames, OrderedCollections\n\njulia> tables = OrderedDict{Symbol,DataFrame}();\n\njulia> for (name, row) in results\n           push!(get!(tables, name, DataFrame()), row)\n       end\n\njulia> tables[:person]\n4×3 DataFrame\n Row │ id                                 first_name  last_name\n     │ UUID                               String      String\n─────┼──────────────────────────────────────────────────────────\n   1 │ f243cfbd-7ba0-4d65-aac3-60d02d83…  Bob         Brown\n   2 │ 109b935e-70fd-42b9-a623-aeefc355…  Alice       Williams\n   3 │ 598c059f-4138-41f5-8350-6c47cc43…  Bob         Johnson\n   4 │ 3f79f2fa-5830-41b1-8a8f-47b2d76b…  Carol       Smith\n\njulia> tables[:visit]\n9×4 DataFrame\n Row │ id                                 person_id                          index  date\n     │ UUID                               UUID                               Int64  Date\n─────┼─────────────────────────────────────────────────────────────────────────────────────────\n   1 │ 9760d38f-0749-40f4-973d-b8818f31…  f243cfbd-7ba0-4d65-aac3-60d02d83…      1  1972-07-17\n   2 │ 4855b672-64be-468b-b3a1-dd7a595c…  f243cfbd-7ba0-4d65-aac3-60d02d83…      2  1982-10-29\n   3 │ a3be2559-9670-438c-ae30-a7c1f469…  f243cfbd-7ba0-4d65-aac3-60d02d83…      3  1983-12-30\n   4 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  f243cfbd-7ba0-4d65-aac3-60d02d83…      4  1995-04-30\n   5 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  109b935e-70fd-42b9-a623-aeefc355…      1  1972-02-10\n   6 │ 41f0d3df-1ad7-4906-8995-49e43876…  109b935e-70fd-42b9-a623-aeefc355…      2  1982-04-07\n   7 │ 033dd1c4-8700-4d27-91e9-05e2d2aa…  598c059f-4138-41f5-8350-6c47cc43…      1  1983-06-09\n   8 │ 69b6b83c-1825-49c6-ae26-c902dc01…  598c059f-4138-41f5-8350-6c47cc43…      2  1986-09-30\n   9 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  3f79f2fa-5830-41b1-8a8f-47b2d76b…      1  1977-07-21\n\njulia> tables[:visit]\n16×2 DataFrame\n Row │ visit_id                           symptom\n     │ UUID                               String\n─────┼────────────────────────────────────────────────\n   1 │ 9760d38f-0749-40f4-973d-b8818f31…  Runny nose\n   2 │ 4855b672-64be-468b-b3a1-dd7a595c…  Cough\n   3 │ 4855b672-64be-468b-b3a1-dd7a595c…  Runny nose\n   4 │ a3be2559-9670-438c-ae30-a7c1f469…  Muscle Loss\n   5 │ a3be2559-9670-438c-ae30-a7c1f469…  Muscle Loss\n   6 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  Muscle Loss\n   7 │ 1b20aa89-22c8-4c71-84c4-5a95267f…  Fainting\n   8 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  Fever\n   9 │ 7366ea7e-f6f5-41c9-8c48-4e0b060c…  Fever\n  10 │ 41f0d3df-1ad7-4906-8995-49e43876…  Runny nose\n  11 │ 41f0d3df-1ad7-4906-8995-49e43876…  Chills\n  12 │ 033dd1c4-8700-4d27-91e9-05e2d2aa…  Chills\n  13 │ 69b6b83c-1825-49c6-ae26-c902dc01…  Chills\n  14 │ 69b6b83c-1825-49c6-ae26-c902dc01…  Fever\n  15 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  Fatigue\n  16 │ 5198d75c-8e1c-4d93-8ae9-ab976c44…  Fatigue","category":"page"},{"location":"","page":"API Documentation","title":"API Documentation","text":"Here we use an OrderedDict to preserve insertion order. This ensures that tables which are used downstream in the DAG show up earlier in the dictionary. This allows uploading the tables into e.g. databases which make foreign key checks smoother, since one simply needs to upload in the order the resulting OrderedDict uses.","category":"page"}]
}