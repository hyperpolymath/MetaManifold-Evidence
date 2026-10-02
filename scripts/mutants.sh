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
target=MetaManifold/Evidence/Counts.agda
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# Apply one sed expression to a copy of the module and require that the copy
# differs from the original and fails to type-check.
kill_mutant() {
  local label=$1 expr=$2 dir
  dir="$work/$label"
  mkdir -p "$dir"
  cp -r agda/src/. "$dir/"
  sed -i -e "$expr" "$dir/$target"
  if cmp -s "agda/src/$target" "$dir/$target"; then
    echo "ERROR: mutant $label did not change the module (stale pattern)" >&2
    exit 1
  fi
  if "$prover" --safe --without-K --no-libraries --ignore-interfaces \
       -i "$dir" -i "$ret_src" "$dir/$target" >"$dir.log" 2>&1; then
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
kill_mutant threshold 's/^verdict y n with n < y$/verdict y n with n < suc y/; s/^verdict-sound y n with n < y in eq$/verdict-sound y n with n < suc y in eq/'
# Zero reads with zero noise reported as unresolved.
kill_mutant zero-case '0,/^\.\.\.     | zero  = refuted$/s//...     | zero  = unresolved/'
# Noise counted on one side only: under-counting worlds removed from the model.
kill_mutant one-sided 's/^observed (world b d under) = b$/observed (world b d under) = b + d/'
echo 'PASS: all mutants killed'
