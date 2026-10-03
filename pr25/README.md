# PR #25 — clr_lm: prevalence before replacement, Welch instead of `lm`

This directory is the evidence behind the follow-up commit to
`MetaManifold-WebUI#25`. It is here rather than only in the PR because the token
available in the sandbox can write to this repository and not to the fork — and
that turned out to matter: the container was rebuilt partway through this work
(`/home/user/tools`, the WebUI clone, the Agda venv and the node modules all
went), and only what had been committed and pushed here survived. Re-cloning the
fork, applying the patch, and re-running everything reproduced the verified
state exactly, which is the round-trip check that the patch is the whole change.

## The commit

`0001-Test-each-CLR-difference-with-Welch-s-t-test-and-fil.patch` is
`df468ae0165fecd6c8198dfeecd090f6d5174fae`, made in a local clone of the fork and
not yet on the PR branch. This sandbox cannot push it by any route: `git push`
returns 403, and `gh api -X PATCH .../git/refs/heads/feat/differential-clr`
returns `Resource not accessible by integration` even though `gh api` reports
`push: true` for the user — the credential is an App installation token scoped to
this repository. The patch applies to `feat/differential-clr` at `1ee3e71`
(`git apply --check`, and `git am` run twice, including after the rebuild):

```sh
git clone https://github.com/hyperpolymath/MetaManifold-WebUI.git
cd MetaManifold-WebUI
git fetch origin feat/differential-clr && git checkout feat/differential-clr
git am /path/to/pr25/0001-*.patch
git push origin feat/differential-clr
```

It changes 14 files: `src/analysis/zero_replacement.jl`, `src/analysis/differential.jl`,
`src/server/routes/analysis.jl`, `config/defaults/pipeline.yml`, `renv.lock`,
`R/_renv_dependencies.R`, `.github/workflows/ci.yml`, both Julia test files,
and five files in `frontend/src`.

## What is in here

| path | what it is |
| --- | --- |
| `tools/clr_model.py` | An independent implementation of the whole `clr_lm` chain — `cmultRepl`'s arithmetic, the CLR, Welch's and the pooled t test, Benjamini-Hochberg — written from `cran/zCompositions/R/cmultRepl.R` rather than from the Julia, so the two can disagree. Every literal in the shipped tests came from here. |
| `tools/fixture.py` | Prints those same quantities as Julia literals, which is how the test files were written without typing numbers. |
| `tools/jl_parse.py` | tree-sitter parse gate for the five touched `.jl` files. Syntax only: it is a licence to hand the file to `julia --project=. test/runtests.jl`, not a substitute. || `rcheck/patch_*.py` | not shipped: the two one-off editors used to extend the harness in place |
| `rcheck/extract.py` | Lifts the R strings out of the shipped Julia sources **verbatim** — `_REPLACE_R`, `_FIT_WELCH_R`, and `_FIT_R` for the negative-binomial path — and builds one webR script that feeds them the fixtures the Julia tests use. |
| `rcheck/run.mjs` | Runs that script in real R (webR 0.6.0, R 4.6.0) with `zc/R/*.R` — the pinned 1.6.2 sources of zCompositions — evaluated into the global environment, since webR sees no host filesystem. |
| `rcheck/check.py` | Fails unless R's answer matches the model on all 110 emitted lines, *and* unless every constant with more than eight figures in the two Julia test files is a number R itself printed. |
| `rcheck/generated/` | The extracted bodies, the generated harness, and `out.txt`, the record of the last run. |
| `rcheck/zc/` | The pinned package sources the harness evaluates instead of installing (DESCRIPTION plus `cmultRepl.R`, `zPatterns.R`). |

## Re-running the check

```sh
cd pr25/rcheck
npm install webr@0.6.0                  # R compiled to WebAssembly; needs node >= 17
export METAMANIFOLD_WEBUI=/path/to/MetaManifold-WebUI    # defaults to /home/user/...
python3 extract.py && node run.mjs && python3 check.py
```

`extract.py` and `check.py` find `../tools` on their own; set
`METAMANIFOLD_TOOLS` if the model lives elsewhere. Expected:

```
110 tagged lines from R, 110 expectations checked
R and the model agree on every line, and every long literal in the tests is one
R itself printed.
```

`check.py` exits non-zero on a mismatch, on a line R did not print, on a line it
cannot explain, and on a test literal that appears nowhere in R's output.

## Numbers R itself confirmed

| quantity | R 4.6.0 |
| --- | --- |
| `A1`'s imputed row, sparse fixture at `min_prevalence = 0.25` | `0.43243727598566306 0.43243727598566306 0.062903225806451607 0.072222222222222215` |
| largest imputed share of a sample's total | `0.13512544802867382` |
| the same table with the rare taxa left in: `A1`'s mass | `1.2375786885245903` (so the refusal says 123.8%, bound 0.526) |
| what `cmultRepl` returns for that over-eaten row | `-0.11878934426229515` — a negative *observed* entry, hence the guard |
| `p`'s estimate, filter-then-replace versus replace-then-filter | `0.94208153004477513` versus `1.2128631882349956` |
| `q`: Welch's p, pooled p, Welch df | `0.098203625579598358`, `0.037278838082443477`, `3.0413580844458199` |
| `t_up` df on the 12-versus-12 fixture | `21.773496214508405` (pooled would print 22) |
| messages R gives that the wrapper must never relay | `Label 0 was not found in the data set`, `X contains negative values`, `X must be a data matrix with at least two rows` |

## What was run, and what was not

Run here, and clean:

- `node run.mjs` and `python3 check.py`: 110 tagged lines, all agreeing with the
  model — `cmultRepl` on every fixture, the full replace → CLR → Welch chains,
  the three refusal messages R gives, the three notes the fit writes when it
  cannot estimate, the shapes and column names the Julia indexes by name, and
  Benjamini-Hochberg against `stats::p.adjust`.
- The two R bodies are the shipped ones, read out of the Julia at run time; the
  only edit is dropping the `zCompositions::` prefix, because webR has the
  sources rather than an installed package.
- All five touched `.jl` files through `tools/jl_parse.py`.
- `frontend`: `bun test src` (33 pass, 0 fail, 78 expects), `bun run typecheck`,
  and `bunx vite build` (built, only the pre-existing chunk-size warning).
- This repository's own gates at the commit that added this directory:
  `scripts/check.sh` then `scripts/mutants.sh` → `PASS: counts proofs and all 5
  expected rejections`, `PASS: all mutants killed`, `AGDA_GATE_EXIT=0`, under Agda
  2.7.0.1 (CI pins 2.6.4.3; the proofs verify under both).

Not run here, and CI's to confirm:

- `julia --project=. test/runtests.jl zero_replacement differential`. Two separate
  dead ends: RCall cannot start without a host `libR.so` (there is no R here and
  no toolchain to build one), and no Julia binary is reachable —
  `julialang-s3.julialang.org` does not answer, and the GitHub release asset 404s
  with `objects.githubusercontent.com` blocked. So the Julia side is verified by
  construction — the R it will call is the R that was run, and the pure-Julia
  parts were checked by the model — rather than by execution. Every R-facing test
  skips loudly rather than passing quietly, which is also why `ci.yml` now
  requires zCompositions explicitly after `renv::restore()`.
