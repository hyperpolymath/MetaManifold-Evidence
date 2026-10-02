#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
#
# Gate self-test for the Julia side of the grid certificate. First the
# committed CountsJuliaTable.agda must equal what the package renders now.
# Then each mutant corrupts the package's verdict code in a copy, and the
# table that copy renders must differ from the committed one, so a CI
# regenerate-and-diff step cannot pass vacuously.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
julia_bin="${JULIA:-julia}"
table=agda/src/MetaManifold/Evidence/CountsJuliaTable.agda
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Print the table the package at $1 (a julia/ project directory) renders.
render() {
  "$julia_bin" --project="$1" -e 'using MetaManifoldEvidence: certificate_agda; print(certificate_agda())'
}

render julia >"$work/now.agda"
if ! cmp -s "$table" "$work/now.agda"; then
  diff -u "$table" "$work/now.agda" || true
  echo "ERROR: $table is stale; run julia --project=julia julia/gen/emit_table.jl" >&2
  exit 1
fi
echo "PASS: committed table matches the package"

# Apply one sed expression to counts.jl in a copy of the package and require
# that the copy changed and renders a table different from the committed one.
kill_mutant() {
  local label=$1 expr=$2 dir
  dir="$work/$label"
  mkdir -p "$dir"
  cp -r julia "$dir/julia"
  sed -i -e "$expr" "$dir/julia/src/counts.jl"
  if cmp -s julia/src/counts.jl "$dir/julia/src/counts.jl"; then
    echo "ERROR: mutant $label did not change counts.jl (stale pattern)" >&2
    exit 1
  fi
  if ! render "$dir/julia" >"$dir/table.agda"; then
    echo "ERROR: mutant $label failed to render; it must render a wrong table, not crash" >&2
    exit 1
  fi
  if cmp -s "$table" "$dir/table.agda"; then
    echo "ERROR: mutant survived: $label" >&2
    exit 1
  fi
  echo "PASS: killed $label"
}

# Non-strict entailment threshold.
kill_mutant threshold 's/^    noise_bound < reads \&\& return ENTAILED$/    noise_bound <= reads \&\& return ENTAILED/'
# The lower end no longer clamps at zero.
kill_mutant no-clamp 's/^    return (lo = max(0, reads - noise_bound), hi = reads + noise_bound)$/    return (lo = reads - noise_bound, hi = reads + noise_bound)/'
echo 'PASS: all Julia mutants killed'
