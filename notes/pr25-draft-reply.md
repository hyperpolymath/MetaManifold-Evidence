# Draft reply to the review on PR #25

Post as a comment on `hyperpolymath/MetaManifold-WebUI#25` (the review is a single
`CHANGES_REQUESTED` body with no inline comments, so one reply covers it).

---

All four are in, as two commits on top of `1ee3e71`.

**Filtering before replacement.** `min_prevalence` now decides the composition, not only the test
list. `clr_composition(counts, prevalence, min_prevalence)` returns the taxa that have reads *and*
reach the threshold (plus the ones that have no reads anywhere, which get a status rather than
silently vanishing); the replacement runs over those taxa, the sample is transformed over exactly
those, and the threshold is not applied a second time afterwards. Your table, re-measured: with the
replacement across every observed taxon the imputed values are a median 47% of the sample total and
exceed the total itself in 9 of 66 samples; filtering at 0.1 first, median 1%, max 8%.

The guard that refuses a sample whose zeros would take over its total moved in front of R entirely,
and its advice is now computed rather than asserted. It gives the largest `delta` that sample admits
and the `min_prevalence` that clears it — `floor(p·n)+1 / n`, from the same arithmetic that raised
the refusal — and a test follows the advice and runs the table at it. A taxon dropped by the
threshold takes its reads out of the total as well as its detection limit out of the sum; that was
the case where the old message could tell you to do something that still refused.

One asymmetry I kept: a taxon with zero reads is excluded at *any* `min_prevalence`, including 0.
There is no detection limit to replace its zeros with, so there is no threshold at which it can
join a composition. Its row says that.

**Statistics in R.** The replacement is `zCompositions::multRepl` at `frac = delta` through RCall,
asked with `z.delete = FALSE, z.warning = 1` so the package cannot quietly delete the samples and
taxa whose counts the result is about to report: each sample is closed to its own total, detection
limits are handed over per cell on that scale, and the table is re-opened, which leaves the observed
counts exactly as they were. `zCompositions` 1.6.2 and its imports `NADA` 1.6-1.2 and `truncnorm`
1.0-9 are in `renv.lock`, declared in `R/_renv_dependencies.R`, and required in both CI checks.
Nothing else compositional is pinned: no `glmGamPoi`, no `compositions`, only what `multRepl` itself
needs. The three lockfile entries were written by hand and should be regenerated with
`renv::snapshot()` under R 4.5.0 — I would rather that show up as a re-snapshot diff than have the
lock silently disagree with CRAN's metadata, and `truncnorm` is the only one of the three that
compiles.

The per-taxon model is `stats::t.test`, one call per taxon inside the R lock, and every number it
returns is reconciled before it is reported: R's own estimate and statistic must agree with a
standard error computed from the same two groups (`|t − est/se| ≤ 1e-8`), and R's p-value with the
two-sided tail of its own t and df. A taxon that does not reconcile is `failed` with that as its
note, not a row with numbers I picked instead of the ones that disagreed.

`mult_repl_reference` — the Julia formula — stays, because the refusals need the imputed mass
before R is called, and because "R and the reference agree" is then a test rather than an
assumption. It is not a fallback: no `via` is silently substituted for another. Every outcome says
which code made it, `zCompositions::multRepl`, `julia reference`, or `none (no zeros to replace)`
for a table with no zeros at all, which needs no package. A missing zCompositions raises
`ZCompositionsUnavailable`, which the route maps to 503 next to the existing `MASSUnavailable` arm.

**Welch.** `t.test(contrast_values, reference_values, var.equal = FALSE)`, so the estimate is
already contrast minus reference rather than whichever way a formula method's factor levels
happened to order it, and the statistic carries the estimate's sign. The two-vector form is
deliberate: the formula method's estimate is `mean(level 1) − mean(level 2)`, which for a
`(reference, contrast)` level vector is the negation of what this app promises. A test pins the
estimate against a direct `t.test` call and against the definition (difference of group mean CLRs),
and checks it is *not* the pooled p-value that `lm` would have given on the same numbers.

This costs one thing that `lm` did not: `clr_lm` now needs two samples in each group, because a
variance cannot be estimated from one, so the group guard is method-aware — `clr_lm` ≥ 2 per group,
`nb_glm` unchanged at ≥ 1 each and ≥ 3 in total. That is a narrower `clr_lm` than before; it is
Welch's requirement, not mine, and it says so with the counts.

**Sparse regression test.** `test/unit/test_differential.jl` builds a 40 x 24 table, ~95% zeros:
four common taxa and twenty singletons seen in one sample each. At `min_prevalence = 0` the run is
refused, naming the sample (`s1`: 780 imputed against a total of 212) and the threshold that fixes
it; at 0.05 the same table runs, with `n_taxa_in_composition = 4`, `zeros_replaced = 0`,
`n_filtered = 20` and every singleton row `filtered` with the reason. Same fixture, same groups,
only the threshold changed — which is the claim the whole change is making. `test_zero_replacement.jl`
covers the guard and the advice on a 4 x 4 table where the refusal, the advice and the run are all
checkable by hand, and gates the R comparisons on the package being present so an absent zCompositions
is a skip with a message rather than a red suite.

**Also:** the summary line under a `clr_lm` result now quotes the median as well as the maximum
share of a sample ("at most X%" alone reads like an all-clear on a table where every sample is mostly
imputed), and names the number that actually controls it — `min_prevalence` chose the composition.
It is `zeroReplacementLine`, next to `configLine` and `effectValue` in `differentialTable.ts`, so it
is tested rather than rendered. `effect` stays `estimate` for `clr_lm`, `log2_fold_change` stays the
key for `nb_glm`, and no config key changed name or meaning, so nothing in a stored run config needs
migrating.

**Verification, and the limit of it:** `bun run test` (32 pass) and `bun run typecheck` are clean.
The Julia side is compiled and run only by CI — I had no Julia toolchain where these commits were
made, so the arithmetic in the guard and the advice is checked by hand and by the tests rather than
by an execution, and the RCall paths are untested until CI runs them. Say the word and I'll push to
`feat/differential-clr`; the first green run is the real review of the R parts.

Refs #102 for the scope, and one follow-up that is not in this PR: `R_PACKAGES` in
`src/core/provenance.jl` records the versions of dada2, Biostrings, ShortRead and vegan into a run's
provenance, and not the packages either differential method actually fits with — MASS for `nb_glm`,
zCompositions for `clr_lm`. Drafted as a separate issue rather than widened in here.
