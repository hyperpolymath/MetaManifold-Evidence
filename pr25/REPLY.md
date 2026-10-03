# Draft reply for MetaManifold-WebUI#25

Not posted: the commit is prepared but this sandbox cannot push to the fork.
`git push` returns 403 and the REST equivalent returns `Resource not accessible
by integration` — the credential is an App installation token scoped to the Arena
repository, so no route writes to `hyperpolymath/MetaManifold-WebUI`.
Apply `0001-*.patch` first, then paste the body below. The evidence it cites is
already pushed: `pr25/` in `MetaManifold-Evidence` at
`27ae7ba830b6f3946095a2e648205345d93a33be`, on branch
`arena/01a10031-metamanifold-evidence`; the patch reproduces the commit
`c5ba8c75bc4bcfb34861cc87f39ceba2dde01284`.

---

Four changes on top of `1ee3e71`, one per objection.

**1. The prevalence filter runs before the replacement, not after.** The order was
replace → CLR → filter, which imputes into every taxon the sequencing happened to
see and then throws most of them away — while the imputed values stay inside the
geometric mean that every reported taxon is divided by. Now: taxa with no reads
anywhere are set aside (they have no observed proportion to cap a replacement
against), `min_prevalence` chooses the composition, and `cmultRepl` replaces the
zeros of exactly that table. The shipped `analysis.differential.min_prevalence` is
`0.25` rather than `0`.

On the six-sample example the two orders do not merely differ in spirit. With
`min_prevalence = 0.5`, replacing over `p, q, rare` and keeping `p, q` afterwards
gives `p` an estimate of `1.2128631882349956` with `p = 0.034360801085094539`;
filtering first gives `0.94208153004477513` with `p = 0.00041107699360433072`.
The 0.27 CLR units between them are the rare taxon's imputed read moving the
denominator of a transform that never reports it. The test asserts both numbers
and that they differ.

**2. A replacement that cannot be made is refused, with the arithmetic.**
`cmultRepl` does not refuse when the imputations outgrow the sample: it scales the
observed entries by `1 - Σ`, and at `Σ ≥ 1` that sends them to zero or, as R
really does here, to `-0.11878934426229515`. The wrapper therefore computes the
same limit R computes — each zero gets `δ · threshold / n_i`, capped at
`δ · c_j`, the taxon's smallest observed proportion — and stops before R is
asked, naming the sample, the share of its total the zeros would hold, and the
largest `δ` that could still work:

```
sample 'A1' has 9 zeros whose replacements at delta = 0.65 would hold 123.8% of
its total, leaving nothing for the taxa it does have. The largest delta that can
still work is below 0.526. Raise analysis.differential.min_prevalence, so that
the composition being replaced over is the one the test is run on, or lower
analysis.differential.replacement_delta to take the zeros one tier at a time.
```

That is the 18S-shaped fixture: 8 samples × 12 taxa, 61 of 96 cells zero, `A1`
carrying two reads. At `min_prevalence` `0.0` and `0.125` it says the above; at
`0.25` the composition is the four taxa the test would report on, four zeros are
imputed in three samples, the largest holds 13.5% of its sample, and the analysis
runs. The bound is `δ / mass` rounded *up*: `mass(δ)/δ` is non-increasing in `δ`,
so it is a true upper bound on what can work — and `0.526` really is above the
root at `0.52521912830844997`, which matters, because `0.5251` does work and a
rounded-down bound would have said it did not.

**3. Welch's t test, and the degrees of freedom in the row.** Each taxon is now
tested with `stats::t.test(x = contrast, y = reference, var.equal = FALSE)`;
`stats::lm` is gone. The estimate is unchanged (it was always the difference of
group means of the CLR, which is what the coefficient computed); what changes is
that each group keeps its own variance, and each row carries `df` so a reader can
see which test ran — 21.773496214508405 on the 12-versus-12 fixture, where the
pooled test would have printed 22.

One thing I want to be explicit about, because I said the opposite earlier: equal
group sizes do *not* make Welch's degrees of freedom the pooled ones. They make
the standard error equal to the pooled one; the df still move, because Welch and
Satterthwaite weights the two variances by their own sample sizes. On the kept
sparse table (3 against 5 samples) `q` is the case that matters: Welch gives
`p = 0.098203625579598358` with 3.04 df and does not reject, the pooled test
borrowing the larger group's variance gives `0.037278838082443477` with 6 df and
does, and the BH-adjusted value crosses 0.05 either way only because of that
swap. A test that cannot estimate anything says so — "the values are constant
across samples", "each group has one distinct value, so no variance can be
estimated", or R's own `not enough 'x' observations` — rather than returning
`t = 0` with `p = 1`.

**4. The filter is honest about what it excluded.** `diagnostics.zero_replacement`
reports `operator`, `delta`, `threshold`, `zeros_replaced`, `n_samples_replaced`,
`n_taxa_in_composition`, `n_taxa_excluded`, `n_taxa_unobserved`,
`max_imputed_fraction`, `median_imputed_fraction`, and `diagnostics.fit_method`
names the test. The table and CSV gained `df`; the config line under the plot
reads `method clr_lm, replacement_delta 0.65, min_prevalence 0.25 (applied before
zero replacement); estimate is a CLR difference, not a fold change`. A study with
R unavailable gets a 503 and `ZCompositionsUnavailable`, not an empty table.

**Pinning.** `zCompositions 1.6.2` plus its dependencies `NADA 1.6-1.2`,
`truncnorm 1.0-9` and `survival 3.8-12` are in `renv.lock`, and `ci.yml` now
`require`s zCompositions in the post-restore loop (a lock entry alone does not
prove it loads). Versions re-read from CRAN, not from memory.

**Tests.** `test/unit/test_zero_replacement.jl` was rewritten: the two cases that
do not need R (the refusal text, the invariants) now run unconditionally, the
`cmultRepl` comparisons skip loudly when the package is absent, and no test
compares against a hand-remembered number. `test/unit/test_differential.jl`
gained the sparse fixture, the filter-before-replacement comparison, the Welch
versus pooled check, `fit_welch`'s three failure notes, and a per-taxon loop that
matches every estimate, p-value and df against a direct `t.test` call.

**Verification, stated precisely.** R is not runnable in the environment I worked
in (no host `libR.so`, so RCall cannot start), so I checked the statistics a
different way: an independent Python re-implementation of the chain, plus a webR
harness that extracts the two R strings *from the shipped Julia sources* and runs
them in real R 4.6.0 with the pinned package's own `cmultRepl.R` — 110 tagged
comparisons, all matching, and a gate that fails if any long literal in either
test file is not a number R printed, if the replacement returns a table of the
wrong shape, or if the fit's columns are renamed. Everything, including `frontend`
(`bun test src`: 33 pass; `bun run typecheck`: clean) is described in
`MetaManifold-Evidence/pr25/README.md` at `27ae7ba830b6f3946095a2e648205345d93a33be`,
which also carries the patch. What I could not run is the Julia test suite itself; that is CI's.

**One scope call I would like a decision on.** `min_prevalence` is one setting for
both methods, so shipping `0.25` also filters rare taxa for `nb_glm`, which is a
behaviour change for existing studies using the negative-binomial path. The old
default there effectively tested everything. If you would rather keep `nb_glm`
untouched, the filter can become `clr_lm`-only with the default restored to `0.0`
for it — small change, but it is your call rather than mine.
