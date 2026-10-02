#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
#
# Type-check the positive set, audit it for escape hatches, then demand that
# every module under agda/reject fails at its intended declaration.
# Requires scripts/fetch-layer-a.sh to have run (or RET_SRC to point at a
# residual-evidence-types src/ directory).
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
prover="${AGDA:-agda}"
ret_src="${RET_SRC:-_build/dependencies/residual-evidence-types/src}"
test -f "$ret_src/ResidualEvidence/Core.agda" || {
  echo "ERROR: residual-evidence-types not found at $ret_src (run scripts/fetch-layer-a.sh)" >&2
  exit 1
}
"$prover" --version
flags=(--safe --without-K --no-libraries --ignore-interfaces --double-check -i agda/src -i "$ret_src")

"$prover" "${flags[@]}" agda/src/MetaManifold/Evidence/All.agda

# Axiom audit. --safe already rejects postulates; this also refuses pragmas
# and holes that would make a pass mean less than it says.
if grep -rnE --include='*.agda' 'postulate|TERMINATING|NON_COVERING|NO_POSITIVITY_CHECK|\{!|--type-in-type|--sized-types|--cubical' agda/src; then
  echo 'ERROR: escape hatch found in the positive set' >&2
  exit 1
fi
echo 'PASS: axiom audit (no postulates, unsafe pragmas or holes)'

mkdir -p _build/check-logs
shopt -s nullglob
rejects=(agda/reject/*.agda)
shopt -u nullglob
if (( ${#rejects[@]} == 0 )); then
  echo 'ERROR: no expected-rejection modules found under agda/reject' >&2
  exit 1
fi
for file in "${rejects[@]}"; do
  name="$(basename -- "$file" .agda)"
  log="_build/check-logs/$name.log"
  if "$prover" "${flags[@]}" -i agda/reject "$file" >"$log" 2>&1; then
    cat "$log"
    echo "ERROR: invalid proof accepted: $name" >&2
    exit 1
  fi
  if ! grep -Eq "/$name\.agda:[0-9]+,[0-9]+" "$log" ||
     ! grep -q 'when checking' "$log" ||
     grep -Eq 'Not in scope|Failed to find|Unsolved|Parse error' "$log"; then
    cat "$log"
    echo "ERROR: unexpected failure while checking $name" >&2
    exit 1
  fi
  echo "PASS: rejected $name at its invalid declaration"
done
echo "PASS: counts proofs and all ${#rejects[@]} expected rejections"
