# PR #25 — clr_lm: prevalence before replacement, Welch instead of `lm`

This directory is the evidence behind the follow-up commit to
`MetaManifold-WebUI#25`. It is here rather than only in the PR because the token
available in the sandbox can write to this repository and not to the fork, so
this is where the work survives.

## The commit

`0001-Test-each-CLR-difference-with-Welch-s-t-test-and-fil.patch` applies to
`feat/differential-clr` at `1ee3e71` (checked with `git apply --check`):

```sh
git clone git@github.com:hyperpolymath/MetaManifold-WebUI.git
cd MetaManifold-WebUI
git fetch origin feat/differential-clr && git checkout feat/differential-clr
git am ~/pr25/0001-*.patch
git push origin feat/differential-clr
```

It changes 14 files: `src/analysis/zero_replacement.jl`, `src/analysis/differential.jl`,
`src/server/routes/analysis.jl`, `config/defaults/pipeline.yml`, `renv.lock`,
`R/_renv_dependencies.R`, `.github/workflows/ci.yml`, both Julia test files,
and five files in `frontend/src`.

## What is in here

| path | what it is |
| --- | --- |
| `model/clr_model.py` | An independent implementation of the whole `clr_lm` chain — `cmultRepl`'s arithmetic, the CLR, Welch's and the pooled t test, Benjamini-Hochberg — written from `cran/zCompositions/R/cmultRepl.R` rather than from the Julia, so the two can disagree. Every literal in the shipped tests came from here. |
| `model/fixture.py` | Prints those same quantities as Julia literals, which is how the test files were written without typing numbers. |
| `rcheck/extract.py` | Lifts the two R strings out of the shipped Julia sources **verbatim** and builds one webR script that feeds them the fixtures the Julia tests use. |
| `rcheck/run.mjs` | Runs that script in real R (webR 0.6.0, R 4.6.0) with `zc/R/*.R` — the pinned 1.6.2 sources of zCompositions — evaluated into the global environment. |
| `rcheck/check.py` | Fails unless R's answer matches the model on all 99 emitted lines, *and* unless every constant with more than eight figures in the two Julia test files is a number R itself printed. |
| `rcheck/generated/` | The generated harness and `out.txt`, the record of the last run. |

## Re-running the check

```sh
cd pr25/rcheck
npm install webr@0.6.0                  # R compiled to WebAssembly; needs node >= 17
export METAMANIFOLD_WEBUI=/path/to/MetaManifold-WebUI
python3 extract.py && node run.mjs && python3 check.py
```

Expected: `99 tagged lines from R, 99 expectations checked` and the line saying
R and the model agree. `check.py` exits non-zero on any mismatch, on a missing
line, and on a line it cannot explain.

## What was run, and what was not

Run here, and clean:

- `python3 check.py` — the model against R, including `cmultRepl` on the sparse
  fixture, the three refusal messages R gives, and the three notes the fit writes
  when it cannot estimate.
- `node run.mjs` on `generated/harness.R`, whose two R bodies are the shipped
  ones (the only edit is dropping the `zCompositions::` prefix, because webR has
  the sources rather than an installed package).
- All five touched `.jl` files through a tree-sitter parse gate.
- `bun test src` (33 pass, 0 fail) and `bun run typecheck` in `frontend/`.

Not run here, and CI's to confirm:

- `julia --project=. test/runtests.jl zero_replacement differential`. There is no
  Julia in this sandbox, and RCall cannot load without a host `libR.so`, so the
  Julia side is verified by construction (the R it calls is what was run) rather
  than by execution. `Pkg.test()` also needs `renv::restore()` to have installed
  zCompositions, which is why `ci.yml` now requires it explicitly.
- `Agda` and the mutant gates in this repository are green independently of the
  change (`AGDA_GATE_EXIT=0`, all mutants killed, 2026-10-03).
