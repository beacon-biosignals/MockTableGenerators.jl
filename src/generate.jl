abstract type TableGenerator end

# TODO: The table name for a generator is expected to be unchanged over multiple `emit`
# calls. We currently only call this function once per DAG node visit so any generator
# relying on changing this over time will fail.

"""
    visit!(rng, g::TableGenerator, deps)

Used in [`generate`](@ref) to update state each time the node is visited in the DAG.
When a `TableGenerator` creates a batch of rows this function is only called once.
"""
visit!(rng, g::TableGenerator, deps) = nothing

"""
    table_key(::TableGenerator) -> Symbol

States the name of the table associated with the subtype instance of `TableGenerator`. The
defined name will be included in the DAG output to identify the row's table.
"""
function table_key end

"""
    dependency_key(::TableGenerator) -> Symbol

States the key used in the dependency dictionary (`deps`) to uniquely identify this
`TableGenerator`. When undefined `dependency_key` will fall back on calling `table_key`.

See also: [`emit!`](@ref), [`table_key`](@ref)
"""
dependency_key(g::TableGenerator) = table_key(g)

"""
    num_rows(rng::AbstractRNG, g::TableGenerator, state=nothing) -> Int
    num_rows(rng::AbstractRNG, g::TableGenerator) -> Int

Returns the number of rows that should be produced for this DAG node visit. The number of
rows can vary between DAG visits.
"""
function num_rows end

"""
    emit!(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any}, state=nothing)
    emit!(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any})

Produces a single row from the table generator `g`. Dependent generators will be passed the
contents of the rows they depend on via `deps` and indexed by the result of
`dependency_key`. Any state returned from `visit!(g, ...)` will be passed into this function
via `state` allowing row generation to be conditional on previous rows created by this
generator.
"""
function emit! end

# TODO: Probably should be dropped but are nice as they reduce churn while iterating on design
num_rows(rng, g::TableGenerator, state::Nothing) = num_rows(rng, g)
emit!(rng, g::TableGenerator, deps, state::Nothing) = emit!(rng, g, deps)


"""
    generate([rng::AbstractRNG=GLOBAL_RNG], dag; size::Integer=10) -> Channel{Pair{Symbol, <:Any}}

Traverses the `dag` and generates the records specified by the [`TableGenerator`](@ref)
of each node. Returns a `Channel` of size `size` comprising `table_key => record` pairs.
"""
generate(dag; kwargs...) = generate(GLOBAL_RNG, dag; kwargs...)

function generate(rng::AbstractRNG, dag; size::Integer=10)
    channel = Channel{Pair{<:Symbol,<:NamedTuple}}(size) do ch
        return generate(rng, dag) do table, row
            return put!(ch, table => row)
        end
    end

    return channel
end

"""
    generate(callback, rng::AbstractRNG, dag) -> Nothing

Traverses the `dag` and generates the records specified by the [`TableGenerator`](@ref)
of each node, and then executes `callback(table_key, record)` on each one.
"""
function generate(callback, rng::AbstractRNG, dag)
    return _generate!(callback, rng, dag, Dict())
end

function _generate!(callback, rng::AbstractRNG, dag::AbstractVector, deps)
    for node in dag
        _generate!(callback, rng, node, deps)
    end
    return nothing
end

function _generate!(callback, rng::AbstractRNG, dag::Pair{<:TableGenerator,<:Any}, deps)
    return _generate!(callback, rng, first(dag)=>[last(dag)], deps)
end

function _generate!(callback, rng::AbstractRNG, dag, deps)
    return _generate!(callback, rng, collect(dag), deps)
end

function _generate!(callback, rng::AbstractRNG, dag::Pair{<:TableGenerator,<:AbstractVector}, deps)
    gen, nodes = dag

    state = visit!(rng, gen, deps)
    t_key, d_key = table_key(gen), dependency_key(gen)
    n = num_rows(rng, gen, state)
    for _ in 1:n
        row = emit!(rng, gen, deps, state)
        callback(t_key, row)

        # Dependents need access to the data in `row` but we need to avoid mutating the
        # passed in object when we propagate back up the tree.
        new_deps = copy(deps)
        new_deps[d_key] = row

        for node in nodes
            _generate!(callback, rng, node, new_deps)
        end
    end
    return nothing
end

function _generate!(callback, rng::AbstractRNG, gen::TableGenerator, deps)
    state = visit!(rng, gen, deps)
    t_key = table_key(gen)
    n = num_rows(rng, gen, state)
    for _ in 1:n
        row = emit!(rng, gen, deps, state)
        callback(t_key, row)
    end
    return nothing
end
