#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
#
# Fetch the generic libraries this package builds on into _build/dependencies,
# by exact commit. A checkout that does not resolve to the pinned commit is a
# failure, never a fallback to whatever the remote currently serves.
set -euo pipefail
cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.."
deps=_build/dependencies

# Fetch one repository at one pinned commit into $deps/<name>.
fetch() {
  local name=$1 repo=$2 sha=$3 dir
  dir=$deps/$name
  if [[ ! -d "$dir/.git" ]]; then
    git init -q "$dir"
    git -C "$dir" remote add origin "https://github.com/$repo.git"
  fi
  git -C "$dir" fetch -q --depth 1 origin "$sha"
  git -C "$dir" checkout -q --detach FETCH_HEAD
  test "$(git -C "$dir" rev-parse HEAD)" = "$sha"
  echo "$name @ $sha"
}

mkdir -p "$deps"
fetch residual-evidence-types hyperpolymath/residual-evidence-types 62d749075425ec32a5aa150d8bc64bf05a7e542f
