abstract type TableGenerator end

# TODO: The table name for a generator is expected to be unchanged over multiple `emit`
# calls. We currently only call this function once per DAG node visit so any generator
# relying on changing this over time will fail.

"""
    visit!(g::TableGenerator, deps)

Function allows generates to update state each time the node is visited the the DAG. When
a `TableGenerator` creates a batch of rows this function is only called once.
"""
visit!(g::TableGenerator, deps) = nothing

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
    num_rows(g::TableGenerator, state=nothing) -> Int
    num_rows(g::TableGenerator) -> Int

Returns the number of rows that should be produced for this DAG node visit. The number of
rows can vary between DAG visits.
"""
function num_rows end

"""
    emit(g::TableGenerator, deps::Dict{Symbol,<:Any}, state=nothing)
    emit(g::TableGenerator, deps::Dict{Symbol,<:Any})

Produces a single row from the table generator. Dependent generators will be passed the
contents of the rows they depend on via `deps` and indexed by the result of
`dependency_key`. Any state returned from `visit!(g, ...)` will be passed into this function
via `state` allowing row generation to be conditional on previous rows created by this
generator.
"""
function emit! end

# TODO: Probably should be dropped but are nice as they reduce churn while iterating on design
num_rows(g::TableGenerator, state::Nothing) = num_rows(g)
emit!(g::TableGenerator, deps, state::Nothing) = emit!(g, deps)

function generate(dag; size::Integer=10)
    channel = Channel(size) do ch
        return generate(dag) do table, row
            return put!(ch, table => row)
        end
    end

    return channel
end

function generate(callback, dag)
    return _generate!(callback, dag, Dict())
end

function _generate!(callback, dag::AbstractVector, deps)
    for node in dag
        _generate!(callback, node, deps)
    end
    return nothing
end

function _generate!(callback, dag::Pair{<:TableGenerator,<:Any}, deps)
    gen, nodes = dag

    state = visit!(gen, deps)
    t_key, d_key = table_key(gen), dependency_key(gen)
    n = num_rows(gen, state)
    for _ in 1:n
        row = emit!(gen, deps, state)
        callback(t_key, row)

        # Dependents need access to the data in `row` but we need to avoid mutating the
        # passed in object when we propagate back up the tree.
        new_deps = copy(deps)
        new_deps[d_key] = row

        for node in nodes
            _generate!(callback, node, new_deps)
        end
    end
    return nothing
end

function _generate!(callback, gen::TableGenerator, deps)
    state = visit!(gen, deps)
    t_key = table_key(gen)
    n = num_rows(gen, state)
    for _ in 1:n
        row = emit!(gen, deps, state)
        callback(t_key, row)
    end
    return nothing
end
