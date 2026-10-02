# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

"""
    MetaManifoldEvidence

Evidence Mode for MetaManifold as an independent package: presence verdicts
for read counts under a noise bound, each one backed by a theorem in
`agda/src/MetaManifold/Evidence/Counts.agda`, served over HTTP beside a
running MetaManifold without importing it.
"""
module MetaManifoldEvidence

using HTTP
using JSON3
using SHA: sha256
using ResidualEvidenceTypes: Case, Verdict, ENTAILED, REFUTED, UNRESOLVED, INCONSISTENT

export CountWorld, latent, observed, count_case, fibre, count_verdict,
       CountsTable, read_tsv, table_from_rows, evaluate, as_count,
       receipt, verify_receipt, canonical_tsv, verdict_name, MODEL, PROOF_PINS,
       fetch_counts, router, serve, DEFAULT_PORT,
       CERTIFICATE_BOUND, certificate_rows, certificate_agda

include("counts.jl")
include("table.jl")
include("receipt.jl")
include("client.jl")
include("server.jl")
include("certificate.jl")

end
