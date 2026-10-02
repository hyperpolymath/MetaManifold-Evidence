# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

"Model identifier recorded in every receipt."
const MODEL = "counts-interval-v1"

"The proved artefacts the verdicts rest on, by tag and commit."
const PROOF_PINS = (
    metamanifold_evidence = "v0.1.1 (f155885dd6d2c55e32796a74f48391d266ef27f0)",
    residual_evidence_types = "62d749075425ec32a5aa150d8bc64bf05a7e542f",
)

"""
    canonical_tsv(table) -> String

A canonical serialisation of the input, used for the receipt's digest:
tab-separated, `\\n` line ends, empty field for a non-count cell.
"""
function canonical_tsv(table::CountsTable)
    io = IOBuffer()
    println(io, join([table.id_column; table.samples], '\t'))
    for i in eachindex(table.ids)
        cells = [c === nothing ? "" : string(c) for c in table.counts[i, :]]
        println(io, join([table.ids[i]; cells], '\t'))
    end
    return String(take!(io))
end

"""
    receipt(table, noise_bound, results) -> Dict

What was decided, from what, under which model and proofs. Deterministic:
the same input and bound always give the same receipt, so it can be stored
beside a report and re-checked with [`verify_receipt`](@ref).
"""
function receipt(table::CountsTable, noise_bound::Integer, results)
    tally = Dict("entailed" => 0, "refuted" => 0, "unresolved" => 0, "not_a_count" => 0)
    for r in results, c in r.cells
        key = c.verdict === nothing ? "not_a_count" : verdict_name(c.verdict)
        tally[key] += 1
    end
    return Dict(
        "model" => MODEL,
        "noise_bound" => Int(noise_bound),
        "input_sha256" => bytes2hex(sha256(canonical_tsv(table))),
        "taxa" => length(table.ids),
        "samples" => length(table.samples),
        "verdicts" => tally,
        "proofs" => Dict(String(k) => v for (k, v) in pairs(PROOF_PINS)),
    )
end

"""
    verify_receipt(table, receipt) -> Bool

Recompute the receipt for `table` at the receipt's noise bound and compare.
"""
function verify_receipt(table::CountsTable, r::AbstractDict)
    n = Int(r["noise_bound"])
    return receipt(table, n, evaluate(table, n)) == Dict(String(k) => _plain(v) for (k, v) in r)
end

"""
    _plain(v)

Convert JSON3 values to plain Dict/Int/String so receipts compare by value.
"""
_plain(v::AbstractDict) = Dict(String(k) => _plain(x) for (k, x) in v)
_plain(v::Integer) = Int(v)
_plain(v::AbstractString) = String(v)
_plain(v) = v

"""
    verdict_name(v::Verdict) -> String

The wire name of a verdict: `entailed`, `refuted`, `unresolved` or
`inconsistent`.
"""
verdict_name(v::Verdict) = lowercase(string(v))
