<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# MetaManifold-Evidence

Evidence Mode for [MetaManifold](https://github.com/JoshuaJewell/MetaManifold-WebUI)
as an independent package (tracking `hyperpolymath/MetaManifold-WebUI#7`).

It answers one question per taxon and sample: *given these read counts and
this noise bound, is the taxon present, absent, or undecided?* The answer is
returned with the proof-backed reason, not a score.

This package does **not** import or modify MetaManifold. Its Julia server
reads only what the app already exposes (a counts TSV, or the app's
`POST /api/v1/studies/{study}/runs/{run}/results/tables/{table}/query` route)
and runs beside it.

## Status (honest labels)

| Part | Status |
|---|---|
| Generic residual-evidence semantics (`Candidate`, `Case`, `Holds`) | **proved** upstream in [`residual-evidence-types`](https://github.com/hyperpolymath/residual-evidence-types) (MPL-2.0), pinned by commit |
| Counts model (`agda/src/MetaManifold/Evidence/Counts.agda`) | **proved**, Agda `--safe --without-K`, builtins only, no postulates |
| Interval ends and verdict behaviour (`agda/src/MetaManifold/Evidence/Bounds.agda`) | **proved**, same flags |
| Julia verdict code (`count_verdict`, `fibre` in `julia/src/counts.jl`) | **certified on the grid** reads, noise ∈ 0..12 (169 rows): Agda proves `grid 12 ≡ expected` by `refl` against a table this code generates. Outside the grid it is **tested**, not proved. The closed forms it implements are proved for all naturals |
| Julia server, input contract, receipts, client for the app's query route | **tested** (`julia/test`), against a stub of the route, not yet against a running app |
| Web UI | **not yet built**. Planned increment E0.4 |
| End-to-end run on MiSeq_SOP | **not yet done**. Planned increment E0.5 |

### What `Counts.agda` proves

A world pairs a latent abundance with an observed read count that differs from
it by noise `d` in either direction. The evidence is `d ≤ n`.

- **`fibre⇒interval` / `interval⇒fibre`.** The candidate latents for `y`
  observed reads are exactly the `x` with `y ≤ x + n` and `x ≤ y + n`, which is
  the interval `[y ∸ n, y + n]`. A fibre is two numbers, so nothing needs
  enumerating, however large `n` is.
- **`case`.** Every observation has an admissible world, so counts never yield
  `inconsistent` (`never-inconsistent`).
- **`verdict-sound`.** The closed-form verdict is sound for every constructor
  it returns:
  - `entailed` when `n < y`: every candidate is present;
  - `refuted` when `y = n = 0`: every candidate is absent;
  - `unresolved` otherwise: there is a witness each way.

### What `Bounds.agda` proves

- **`fibre⇒bounds` / `bounds⇒fibre`.** With `lo y n = y ∸ n` and
  `hi y n = y + n` as functions, the fibre is exactly the latents in
  `[lo, hi]`. The two numbers a client shows are proved, not just computed.
- **`view`.** The verdict is characterised completely:
  - `entailed` ⇔ `n < y`;
  - `refuted` ⇔ `y = n = 0`;
  - `unresolved` ⇔ `y ≤ n` and `n ≥ 1`.
- **More noise never strengthens a verdict.**
  - `entailed-anti`: an entailment survives a lower bound.
  - `unresolved-mono`: an unresolved verdict survives a higher bound.
  - `refuted-only-at-zero` / `refuted-fragile`: refuted occurs only at
    `y = n = 0`, and any positive bound turns it into unresolved.

These hold for all natural numbers. They are not a sampled grid.

### What the grid certificate checks

The Julia code the server runs is not itself proved. To tie it to the proofs,
`julia/gen/emit_table.jl` calls `count_verdict` and `fibre` on every read count
and noise bound in 0..12, and writes the 169 rows to
`agda/src/MetaManifold/Evidence/CountsJuliaTable.agda`.
`CountsCertificate.agda` then proves by `refl` that Agda's proved `verdict`,
`lo` and `hi` produce exactly that table. The rows include 78 cells where the
lower end clamps at zero (`n > y`). That is where Julia's `max(0, y − n)` and
Agda's `y ∸ n` could differ.

The two directions are both guarded:

- If the table is edited, Agda refuses the certificate. `mutants.sh` changes
  one verdict, changes one clamp, and drops one row.
- If the Julia code changes, the regenerated table no longer matches the
  committed one. `julia-mutants.sh` requires the committed table to be
  current, and requires a non-strict threshold and a missing clamp each to
  change it.

### How the proofs are checked

`bash scripts/fetch-layer-a.sh && bash scripts/check.sh && bash scripts/mutants.sh && bash scripts/julia-mutants.sh`

- `check.sh` type-checks the positive set and audits it for escape hatches.
  It then requires every module in `agda/reject/` to **fail** at its intended
  declaration. These are claims that must not be provable, such as "entailed
  at `y = n`".
- `mutants.sh` corrupts the model nine ways and requires the proofs to refuse
  each one:
  - an off-by-one threshold;
  - a zero case relabelled as unresolved;
  - a one-sided noise model;
  - an off-by-one lower interval end;
  - monotonicity in the wrong direction;
  - a non-strict entailment threshold in the characterisation;
  - three corruptions of the Julia table (a verdict, a clamp, a missing row).
- `julia-mutants.sh` is described above.

CI runs the Agda steps with Debian's `agda 2.6.4.3` inside a digest-pinned
image. It runs the Julia steps (`Pkg.test()` and `julia-mutants.sh`) with
Julia 1.12.6 from the official tarball, checked against julialang's published
sha256.

## Running the server

```sh
julia --project=julia -e 'using Pkg; Pkg.instantiate()'
julia --project=julia -e 'using MetaManifoldEvidence; serve(; metamanifold_url = "http://127.0.0.1:<app port>")'
```

It listens on `127.0.0.1:47613` (`DEFAULT_PORT`). The routes are:

| Route | What it returns |
|---|---|
| `GET /api/v1/evidence/health` | the model name and the proof pins |
| `GET /api/v1/evidence/fibre?reads=y&noise=n` | the verdict and the interval `[lo, hi]` |
| `POST /api/v1/evidence/verdicts` | one verdict per taxon and sample, plus a receipt |

The `verdicts` body carries a `noise_bound` and one of: an inline `table`, a
`tsv` string, or a `source` (`study`, `run`, `table`, optional `group`). A
`source` is read from the app's results query route.

`ResidualEvidenceTypes.jl` is a dependency pinned by commit through
`[sources]` in `julia/Project.toml` (Julia ≥ 1.11). It is not registered in
General.

## Assumptions to confirm (Joshua)

1. The noise bound is an **absolute number of reads** per cell, not a
   proportion.
2. Latent abundance is a natural number. Reads cannot be negative.

The observation model is one small function (`observed`) and the evidence is
one predicate (`Bounded`). If either assumption is wrong, those are the only
places to change.

## Licence

AGPL-3.0-or-later, matching MetaManifold. The generic libraries it depends on
(`residual-evidence-types`, and later `ResidualEvidenceTypes.jl`) stay
MPL-2.0. They are used, never copied.
