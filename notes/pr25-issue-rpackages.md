# Issue draft: the provenance record does not name the packages the statistics came from

File against `hyperpolymath/MetaManifold-WebUI`. Independent of PR #25, though #25 makes it worse
in a specific way, which is the reason to raise it now.

---

**Title:** `R_PACKAGES` records the pipeline's R packages, not the ones the analysis fits with

**Body:**

`src/core/provenance.jl:331`

```julia
const R_PACKAGES = ["dada2", "Biostrings", "ShortRead", "vegan"]
```

is the list whose DESCRIPTION versions are written into every run's `RRecord`
(`probe_r`, memoised in the server at `src/server/routes/pipeline.jl:127`). It records the four
packages the *pipeline* needs. It does not record the package the *result* came from:

- `analysis.differential.method = "nb_glm"` fits `MASS::glm.nb` per taxon. MASS is not in the list.
- `= "clr_lm"` replaces zeros with `zCompositions::multRepl` and tests with `stats::t.test`.
  zCompositions is not in the list either, as of #25.

So a run's provenance says which `renv.lock` was in effect — the SHA256 of the file is recorded, and
the lock does pin MASS and zCompositions — but the analysis-critical versions have to be recovered
by reading the lockfile that the SHA points at, which the record does not keep. The point of
recording package versions beside the data, rather than only a lockfile hash, is that the numbers in
the record are the ones that made the numbers in the record. `vegan`'s version is captured for an
NMDS ordination on exactly this reasoning; `glm.nb`'s is not, for the p-values.

There is a second reason the list is short, and it constrains the fix: `probe_r` *throws*
`ProbeFailure` for a named package that is not installed

```julia
raw isa AbstractString || throw(ProbeFailure("r",
    "package '$pkg' is not installed in the R library in use"))
```

so adding a package to `R_PACKAGES` makes provenance capture depend on it, on every run, including
runs that never touch the analysis that uses it. Provenance should not become a way for an unrelated
machine to fail a run.

**What I think the fix is.** Record what the run used, not what the repo declares: the differential
route (or `differential_abundance`) knows its method, so the `RRecord` it writes can name
`MASS` for `nb_glm` and `zCompositions` for `clr_lm` — with `probe_r(; packages=...)`, which already
takes the list as a keyword. A missing package then refuses the *analysis* (it already does,
`MASSUnavailable`/`ZCompositionsUnavailable` → 503) rather than breaking every run's provenance, and
the version that produced a table of p-values travels with the table.

**The related drift, same file's neighbourhood:** the set of R packages appears in four places that
have to agree and nothing makes them agree — `R_PACKAGES` above, the list restored and `require()`d
in `.github/workflows/ci.yml` (~142), the "visible from RCall" check in the same workflow (~233),
and `R/_renv_dependencies.R`, which is what `renv::snapshot()` actually reads. #25 hand-edited the
two CI lists. Deriving all of them from `R/_renv_dependencies.R` (or checking that they are equal to
it, in the existing `test/unit/test_install_pins.jl`) is the version of this that stops recurring.

**Tests to add:** an assertion in `test/unit/test_provenance.jl` that a differential run's R record
names the package its method fits, and one that the four lists above agree — the second is the cheap
one and would have caught the first.
