# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
#
# Regenerate agda/src/MetaManifold/Evidence/CountsJuliaTable.agda from the
# package's own verdict code. Run from the repository root:
#   julia --project=julia julia/gen/emit_table.jl

using MetaManifoldEvidence: certificate_agda

const TARGET = joinpath(@__DIR__, "..", "..", "agda", "src", "MetaManifold",
                        "Evidence", "CountsJuliaTable.agda")

write(TARGET, certificate_agda())
println("wrote ", normpath(TARGET))
