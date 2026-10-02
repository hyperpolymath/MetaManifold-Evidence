#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
#
# Gate self-test: each mutant below corrupts the verdict or its model in a
# way a reviewer could plausibly write. The proofs must refuse every one.
# A mutant that still type-checks means the proofs do not constrain that
# behaviour, and the run fails.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
prover="${AGDA:-agda}"
ret_src="$(realpath "${RET_SRC:-_build/dependencies/residual-evidence-types/src}")"
counts=MetaManifold/Evidence/Counts.agda
bounds=MetaManifold/Evidence/Bounds.agda
table=MetaManifold/Evidence/CountsJuliaTable.agda
cert=MetaManifold/Evidence/CountsCertificate.agda
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Apply one sed expression to a copy of the target module and require that
# the copy differs from the original and that the checked module (the target
# itself unless a fourth argument names another) fails to type-check.
kill_mutant() {
  local target=$1 label=$2 expr=$3 check=${4:-$1} dir
  dir="$work/$label"
  mkdir -p "$dir"
  cp -r agda/src/. "$dir/"
  sed -i -e "$expr" "$dir/$target"
  if cmp -s "agda/src/$target" "$dir/$target"; then
    echo "ERROR: mutant $label did not change the module (stale pattern)" >&2
    exit 1
  fi
  if "$prover" --safe --without-K --no-libraries --ignore-interfaces \
       -i "$dir" -i "$ret_src" "$dir/$check" >"$dir.log" 2>&1; then
    echo "ERROR: mutant survived: $label" >&2
    exit 1
  fi
  if grep -Eq 'Parse error|Not in scope' "$dir.log"; then
    cat "$dir.log"
    echo "ERROR: mutant $label died of a syntax error, not a proof failure" >&2
    exit 1
  fi
  echo "PASS: killed $label"
}

# Off-by-one in the entailment threshold.
kill_mutant "$counts" threshold 's/^verdict y n with n < y$/verdict y n with n < suc y/; s/^verdict-sound y n with n < y in eq$/verdict-sound y n with n < suc y in eq/'
# Zero reads with zero noise reported as unresolved.
kill_mutant "$counts" zero-case '0,/^\.\.\.     | zero  = refuted$/s//...     | zero  = unresolved/'
# Noise counted on one side only: under-counting worlds removed from the model.
kill_mutant "$counts" one-sided 's/^observed (world b d under) = b$/observed (world b d under) = b + d/'
# The lower interval end shifted by one read.
kill_mutant "$bounds" lo-off-by-one 's/^lo y n = y - n$/lo y n = y - suc n/'
# Monotonicity claimed in the wrong direction.
kill_mutant "$bounds" mono-direction 's/^unresolved-mono : ∀ {y n n'"'"'} → n ≤ n'"'"' /unresolved-mono : ∀ {y n n'"'"'} → n'"'"' ≤ n /'
# Entailment characterised with a non-strict threshold.
kill_mutant "$bounds" view-threshold 's/^  v-entailed   : suc n ≤ y /  v-entailed   : n ≤ y /'
# The Julia table disagrees with the proved verdict in one row.
kill_mutant "$table" table-verdict "s/^  row 12 12 unresolved 0 24 ∷\$/  row 12 12 entailed 0 24 ∷/" "$cert"
# The Julia table loses the zero clamp on a lower end.
kill_mutant "$table" table-clamp "s/^  row 3 5 unresolved 0 8 ∷\$/  row 3 5 unresolved 1 8 ∷/" "$cert"
# The Julia table drops a row.
kill_mutant "$table" table-missing-row "/^  row 7 7 unresolved 0 14 ∷\$/d" "$cert"
echo 'PASS: all mutants killed'
