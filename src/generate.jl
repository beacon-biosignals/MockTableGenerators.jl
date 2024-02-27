abstract type TableGenerator end

# TODO: The table name for a generator is expected to be unchanged over multiple `emit`
# calls. We currently only call this function once per DAG node visit so any generator
# relying on changing this over time will fail.

"""
    visit!(rng, g::TableGenerator, deps)

Function allows generates to update state each time the node is visited the the DAG. When
a `TableGenerator` creates a batch of rows this function is only called once.
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
    emit(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any}, state=nothing)
    emit(rng::AbstractRNG, g::TableGenerator, deps::Dict{Symbol,<:Any})

Produces a single row from the table generator. Dependent generators will be passed the
contents of the rows they depend on via `deps` and indexed by the result of
`dependency_key`. Any state returned from `visit!(g, ...)` will be passed into this function
via `state` allowing row generation to be conditional on previous rows created by this
generator.
"""
function emit! end

# TODO: Probably should be dropped but are nice as they reduce churn while iterating on design
num_rows(rng, g::TableGenerator, state::Nothing) = num_rows(rng, g)
emit!(rng, g::TableGenerator, deps, state::Nothing) = emit!(rng, g, deps)

generate(dag; kwargs...) = generate(GLOBAL_RNG, dag; kwargs...)

"""
    generate([rng::AbstractRNG=GLOBAL_RNG], dag; buffer::Integer=0)

Execute the provided DAG.  This will create a `Channel` with buffer size
`buffer`, traverse the DAG, and `put!` the output of each `emit!` call onto the
channel.

The return value is the `Channel`.  Use iteration (`for x in channel`) or
`collect` to get the `emit!`ed values.

Any errors thrown during DAG traversal will be propagated to any tasks waiting
on the channel as a `TaskFailedException`.

!!! warning

    Errors may not be surfaced if the channel is closed (i.e. due to an
    unhandled exception) before being `wait`ed on (including
    iterated/`collect`ed).  This can happen even with an un-buffered channel
    (i.e., `size=0`) if the error occurs before anything is `put!` onto the
    channel.

"""
function generate(rng::AbstractRNG, dag; buffer::Integer=0)
    channel = Channel(buffer) do ch
        return generate(rng, dag) do table, row
            return put!(ch, table => row)
        end
    end

    return channel
end

"""
    generate(callback, rng::AbstractRNG, dag)

Execute the DAG, calling `callback(table, row)` on each `emit!`ed `table => row`
pair.

Returns `nothing`.
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

"""
    collect_tables(name_row_pairs) -> NamedTuple

Given an iterator over `table_name => table_row` pairs, e.g. the output of
[`generate`](@ref), collect the rows corresponding to each distinct table name
and return a `NamedTuple` pairing the names with Tables.jl-compliant tables
containing the rows.
"""
function collect_tables(name_row_pairs)
    tables = NamedTuple()
    for (name, row) in name_row_pairs
        if haskey(tables, name)
            push!(tables[name], row)
        else
            tables = merge(tables, (; name => [row]))
        end
    end
    return tables
end

"""
    generate_tables(args...; kwargs...) -> NamedTuple

Return [`collect_tables`](@ref) applied to the output of [`generate`](@ref) called
with the given arguments and keyword arguments.
"""
generate_tables(args...; kwargs...) = collect_tables(generate(args...; kwargs...))
