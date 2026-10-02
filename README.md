<!-- SPDX-License-Identifier: AGPL-3.0-or-later -->
# MetaManifold-Evidence

Evidence Mode for [MetaManifold](https://github.com/JoshuaJewell/MetaManifold-WebUI)
as an independent package (tracking `hyperpolymath/MetaManifold-WebUI#7`).

It answers one question per taxon and sample: *given these read counts and
this noise bound, is the taxon present, absent, or undecided?* The answer is
returned with the proof-backed reason, not a score.

This package does **not** import or modify MetaManifold. It reads what the app
already exposes (the results table query route, or an exported counts table)
and runs beside it.

## Status (honest labels)

| Part | Status |
|---|---|
| Generic residual-evidence semantics (`Candidate`, `Case`, `Holds`) | **proved** upstream in [`residual-evidence-types`](https://github.com/hyperpolymath/residual-evidence-types) (MPL-2.0), pinned by commit |
| Counts model (`agda/src/MetaManifold/Evidence/Counts.agda`) | **proved**, Agda `--safe --without-K`, builtins only, no postulates |
| Julia routes, web UI | **not yet built**. Planned increments E0.3 and E0.4 |
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

### How the proofs are checked

`bash scripts/fetch-layer-a.sh && bash scripts/check.sh && bash scripts/mutants.sh`

- `check.sh` type-checks the positive set and audits it for escape hatches.
  It then requires every module in `agda/reject/` to **fail** at its intended
  declaration. These are claims that must not be provable, such as "entailed
  at `y = n`".
- `mutants.sh` corrupts the verdict three ways and requires the proofs to
  refuse each one:
  - an off-by-one threshold;
  - a zero case relabelled as unresolved;
  - a one-sided noise model.

CI runs all three steps with Debian's `agda 2.6.4.3` inside a digest-pinned
image.

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
