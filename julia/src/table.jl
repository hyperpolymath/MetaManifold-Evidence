# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

# The input contract: a taxon × sample table of read counts.

"""
    CountsTable(id_column, ids, samples, counts)

Read counts with one row per taxon (`ids`, named by `id_column`) and one
column per sample. `counts[i, j]` is an `Int`, or `nothing` where the source
cell was empty or not a natural number.
"""
struct CountsTable
    id_column::String
    ids::Vector{String}
    samples::Vector{String}
    counts::Matrix{Union{Int,Nothing}}
    function CountsTable(id_column, ids, samples, counts)
        size(counts) == (length(ids), length(samples)) ||
            throw(DimensionMismatch("counts is $(size(counts)), expected $((length(ids), length(samples)))"))
        new(String(id_column), String.(ids), String.(samples), counts)
    end
end

"""
    as_count(x) -> Union{Int,Nothing}

A cell value as a read count: a non-negative integer-valued number, or
`nothing` for anything else (missing, fractional, negative, text).
"""
function as_count(x)
    x isa Real || return nothing
    (isfinite(x) && isinteger(x) && x >= 0) || return nothing
    return Int(x)
end
as_count(x::AbstractString) = (v = tryparse(Float64, strip(x)); v === nothing ? nothing : as_count(v))

"""
    read_tsv(io_or_path) -> CountsTable

Read a tab-separated counts table: a header row, the taxon identifier in the
first column, and one column per sample.
"""
read_tsv(path::AbstractString) = open(read_tsv, path)
function read_tsv(io::IO)
    lines = [l for l in eachline(io) if !isempty(strip(l))]
    isempty(lines) && throw(ArgumentError("empty counts table"))
    header = split(lines[1], '\t')
    length(header) >= 2 || throw(ArgumentError("a counts table needs an id column and at least one sample"))
    samples = String.(header[2:end])
    ids = String[]
    counts = Matrix{Union{Int,Nothing}}(nothing, length(lines) - 1, length(samples))
    for (i, line) in enumerate(lines[2:end])
        fields = split(line, '\t')
        length(fields) == length(header) ||
            throw(ArgumentError("row $(i + 1) has $(length(fields)) fields, expected $(length(header))"))
        push!(ids, String(fields[1]))
        for j in eachindex(samples)
            counts[i, j] = as_count(fields[j + 1])
        end
    end
    return CountsTable(String(header[1]), ids, samples, counts)
end

"""
    table_from_rows(rows, columns, sample_columns) -> CountsTable

Build a table from MetaManifold's results-table query response: `rows` are
objects keyed by column name and `sample_columns` are the count columns the
app identified. The id column is the first of OTU, ASV or SeqName present,
falling back to the first non-sample column.
"""
function table_from_rows(rows, columns, sample_columns)
    samples = String.(collect(sample_columns))
    sample_set = Set(samples)
    cols = String.(collect(columns))
    id_column = _id_column(cols, sample_set)
    ids = String[]
    counts = Matrix{Union{Int,Nothing}}(nothing, length(rows), length(samples))
    for (i, row) in enumerate(rows)
        push!(ids, string(_get(row, id_column)))
        for (j, s) in enumerate(samples)
            counts[i, j] = as_count(_get(row, s))
        end
    end
    return CountsTable(id_column, ids, samples, counts)
end

"""
    _get(row, key)

Look up `key` in a row given as a Dict or a JSON3 object.
"""
_get(row::AbstractDict, key::String) = get(row, key, get(row, Symbol(key), nothing))
_get(row, key::String) = get(row, Symbol(key), nothing)

"""
    evaluate(table, noise_bound) -> Vector{NamedTuple}

One entry per row: the taxon id and, for each sample, the reads, verdict and
fibre. A cell whose source value is not a read count gets `verdict = nothing`.
"""
function evaluate(table::CountsTable, noise_bound::Integer)
    _check(0, noise_bound)
    return [(id = table.ids[i],
             cells = [_cell(table.counts[i, j], noise_bound) for j in eachindex(table.samples)])
            for i in eachindex(table.ids)]
end

"""
    _cell(reads, noise_bound)

The evidence for one cell, or a placeholder for a non-count cell.
"""
_cell(::Nothing, ::Integer) = (reads = nothing, verdict = nothing, lo = nothing, hi = nothing)
function _cell(reads::Int, noise_bound::Integer)
    f = fibre(reads, noise_bound)
    return (reads = reads, verdict = count_verdict(reads, noise_bound), lo = f.lo, hi = f.hi)
end

"""
    _id_column(columns, sample_set)

The taxon identifier column: the first of OTU, ASV or SeqName present, or
else the first column that is not a sample.
"""
function _id_column(cols::Vector{String}, sample_set)
    for c in ("OTU", "ASV", "SeqName")
        c in cols && return c
    end
    i = findfirst(c -> !(c in sample_set), cols)
    i === nothing && throw(ArgumentError("no identifier column among $(cols)"))
    return cols[i]
end
