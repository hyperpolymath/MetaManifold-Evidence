# Prompt: rework PR #25 to answer the review

**Target repository:** `hyperpolymath/MetaManifold-WebUI` (the PR's *head* repo, where the
branch lives and where the reviewer looks). Not the fork at
`JoshuaJewell/MetaManifold-WebUI:main` — that is the base, and pushing there would create a
new branch the PR does not track.

**Start from:** `feat/differential-clr`, head commit `1ee3e71` ("Add a CLR linear-model method
for differential abundance"). Push back to the same branch so PR #25 updates in place; if the
working branch must be different, open a new PR from it into
`JoshuaJewell/MetaManifold-WebUI:main` and close #25 with a link.

Fetch it without the fork remote:

```bash
git fetch https://github.com/JoshuaJewell/MetaManifold-WebUI.git pull/25/head:pr25
git checkout -b feat/differential-clr pr25
```

If `gh` is authenticated against an account with write access to
`hyperpolymath/MetaManifold-WebUI` (`gh api repos/hyperpolymath/MetaManifold-WebUI --jq .permissions`
should show `push: true`), the push is `git push origin HEAD:refs/heads/feat/differential-clr`.
The PR has `maintainerCanModify: true`, so the base owner can also push.

---

## The task

PR #25 adds `analysis.differential.method = "clr_lm"`: multiplicative zero replacement, then
the centred log-ratio, then `stats::lm` per taxon with Benjamini-Hochberg. The owner reviewed it
(2026-10-02, `CHANGES_REQUESTED`, no inline comments) and asked for four things. Do all four, in
one stack, on top of `1ee3e71`. Do not restructure the PR, rename its config keys, or add a third
method.

**1. Apply `min_prevalence` before the replacement, not after the transform.**
As written, the replacement runs across *every observed taxon* and only then is `min_prevalence`
used to decide what to test. On a real sparse 18S table (the PR's own fixture is 66 samples x
1490 taxa, ~95% zeros) replacing across all observed taxa means the imputed values are a median
47% of each sample's total — over 100% of the total in 9 of the 66 samples. A "replacement" that
exceeds the total it is inside is a second dataset, not a correction. Filtering first, at
`min_prevalence = 0.1`, brings the median to ~1%. So the threshold must choose the *composition*
the log-ratios are taken over, as well as the taxa tested: pick the taxa, replace their zeros,
transform, test. It is not re-applied after the transform.

**2. Put the statistics in a pinned R package, called through RCall, like `nb_glm` does.**
The replacement and the per-taxon model are currently hand-written Julia. The repo's rule is that
the statistics come from a pinned package so that the version is recorded and the behaviour is the
published one. Zero replacement: `zCompositions::multRepl`. Test: `stats::t.test`. Pin what you
add in `renv.lock`, declare it in `R/_renv_dependencies.R`, and add it to the two package lists in
`.github/workflows/ci.yml` (the post-restore `require()` loop, and the "R packages visible from
RCall" check). A missing package must raise and refuse; never fall back to another implementation
silently. If a Julia implementation stays — and one should, see 1 — label which code produced a
result, in the result itself.

**3. Welch's t test, not the pooled one, and not `lm`.**
`t.test(a, b, var.equal = FALSE)` per taxon. `stats::lm` pools one residual variance across both
groups, which is the assumption these groups routinely violate: the groups are runs or sub-groups,
so they differ in size as well as spread.

**4. A regression test on the sparse case the review is about.**
A fixture with ~95% zeros and a small `min_prevalence` must show both halves of the fix: that the
run is refused while the composition includes the singleton taxa, with the refusal naming the
sample and the threshold that clears it; and that raising the threshold makes it run, with the
diagnostics showing what was and was not imputed. A test of the happy path only would not have
caught the bug.

---

## Facts that cost time to rediscover

- **`cmultRepl` is not the plain count-level rule.** In every version of zCompositions with the
  current signature, `cmultRepl` is the *Bayesian* treatment of count zeros; `method = "CZM"` is
  the "close then replace with `frac * threshold / n`" rule, which is a different imputation from
  the per-taxon-minimum one used here. The Julia code as written implements `multRepl`, so
  `multRepl` is the faithful call. `multRepl(X, label, dl, frac, imp.missing, closure, z.warning,
  z.delete, delta)`: `dl` must be on the scale of `X`; the output stays on the input scale and for
  non-closed input leaves the observed components' absolute values unaltered (so totals are not
  preserved unless you close first and re-open after). `frac` replaced the name `delta` in 1.4.0.
- **zCompositions' defaults delete data.** `z.warning = 0.8` with `z.delete = TRUE` silently drops
  every row and column holding more zeros than that — on an 18S table, the samples and taxa the
  result is supposed to be about. Pass `z.warning = 1, z.delete = FALSE` and do the refusing
  yourself, in Julia, before R is called.
- **`multRepl` wants a composition.** Close each sample to its own total, hand over per-cell
  detection limits divided by the same total, then re-open with `sweep(x, 1, totals, "*")`. The
  observed counts come back exactly as they were.
- **RCall's `R"..."` string interpolates `$`.** `fit$coefficients` inside `R"""..."""` is parsed as
  Julia interpolation of a variable `coefficients`. In `R"..."`/`R"""..."""` snippets use
  `x[["field"]]`; inside `raw"""..."""` constants `$` is fine. Do not copy `$`-extracting lines
  from the existing tests into an interpolated snippet.
- **Julia broadcasting cannot reproduce R's column-major recycling**, and `δ .* dl' ./ totals`
  mis-shapes when `totals` is an `n x 1` matrix. Doing the closure inside the R snippet avoids both.
- **`min_prevalence` filtering must not exclude a taxon's own reads from the total it is compared
  against** when computing what a sample can bear: a taxon that is dropped takes its reads with it.
  Derive any advice about a threshold from the same arithmetic as the refusal, and test that the
  advice works — a message telling the user to set `min_prevalence` to something that still refuses
  is worse than no message.
- **`renv.lock` is hand-editable but not by right.** renv sorts package keys ASCII-wise (uppercase
  first) and `test/unit/test_install_pins.jl` compares only `R.Version` and the Bioconductor
  version against `config/pins.yml`, so adding entries is safe; regenerating with
  `renv::snapshot()` under R 4.5.0 is still what the lockfile should end up as, and any hand-written
  metadata should be said so in the PR text.
- **CI**: Julia 1.12.5 on ubuntu-24.04, ~22 minutes, `bun install --frozen-lockfile` then
  `bun run test && bun run typecheck` for `frontend/`, and the R library is restored from `renv.lock`
  into `.Library` by `install.jl`/CI. Assume you get one or two attempts, so make the tests that do
  not need R or a package (`zCompositions`) run unconditionally and gate the rest on a probe, the
  way `test/unit/test_differential.jl` already does for MASS.
- **House rules:** SPDX header on every file; refusals carry a reason and never a stand-in number; a
  filtered or failed taxon stays in the table with its status; no unrelated churn; docstrings state
  what a number *is*, not only how it is computed.

## Acceptance

- [ ] `min_prevalence` selects the composition; the replacement only ever sees the taxa that
      survive it; nothing is re-filtered after the transform.
- [ ] An over-full sample is refused in Julia before R is called, with advice that is true — and a
      test proves that following the advice makes the run work.
- [ ] Zero replacement is `zCompositions::multRepl` via RCall, pinned in `renv.lock`, declared in
      `R/_renv_dependencies.R`, required in CI; a Julia reference implementation remains, labelled,
      and tested for parity. Missing package → a named exception → 503 from the route.
- [ ] Per-taxon test is Welch's `t.test`, contrast minus reference, with R's statistic and p-value
      reconciled against an independently computed standard error before either is returned.
- [ ] `clr_lm` refuses a group with fewer than two samples; `nb_glm`'s existing guard is untouched.
- [ ] Diagnostics say what was imputed: how many zeros, by which code, and the median *and* maximum
      share of a sample, plus how many samples exceed 10%. The UI's summary line quotes the median,
      because a maximum alone reads like an all-clear.
- [ ] `bun run test && bun run typecheck` clean; the Julia suite green in CI; `nb_glm` results and
      the config keys unchanged (no config migration, no renamed option, no new method).
