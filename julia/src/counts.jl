# SPDX-License-Identifier: AGPL-3.0-or-later
# SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

# The counts model. Each definition names its counterpart in
# agda/src/MetaManifold/Evidence/Counts.agda.

"""
    CountWorld(base, noise, dir)

A world pairing a latent abundance with an observed read count that differs
from it by `noise`. With `dir == :over` the reads exceed the latent; with
`dir == :under` the latent exceeds the reads. (Agda: `World`.)
"""
struct CountWorld
    base::Int
    noise::Int
    dir::Symbol
end

"""
    latent(w::CountWorld)

The world's true abundance. (Agda: `latent`.)
"""
latent(w::CountWorld) = w.dir === :over ? w.base : w.base + w.noise

"""
    observed(w::CountWorld)

The read count the world produces. (Agda: `observed`.)
"""
observed(w::CountWorld) = w.dir === :over ? w.base + w.noise : w.base

"""
    count_case(reads, noise_bound)

The generic finite case for `reads` observed reads under `noise_bound`, built
by enumeration with `ResidualEvidenceTypes.Case`. It is the reference the
closed forms below are tested against, not what the server runs.
"""
function count_case(reads::Integer, noise_bound::Integer)
    _check(reads, noise_bound)
    worlds = [CountWorld(b, d, dir) for b in 0:reads for d in 0:noise_bound
              for dir in (:over, :under)]
    return Case(worlds, observed, reads; evidence = w -> w.noise <= noise_bound)
end

"""
    fibre(reads, noise_bound) -> (lo, hi)

The candidate latent abundances form the interval `lo:hi`.
(Agda: `fibre⇒interval` and `interval⇒fibre`, proved.)
"""
function fibre(reads::Integer, noise_bound::Integer)
    _check(reads, noise_bound)
    return (lo = max(0, reads - noise_bound), hi = reads + noise_bound)
end

"""
    count_verdict(reads, noise_bound) -> Verdict

The closed-form presence verdict. (Agda: `verdict`, with `verdict-sound`
proving each returned constructor and `never-inconsistent`.)
"""
function count_verdict(reads::Integer, noise_bound::Integer)
    _check(reads, noise_bound)
    noise_bound < reads && return ENTAILED
    reads == 0 && noise_bound == 0 && return REFUTED
    return UNRESOLVED
end

"""
    _check(reads, noise_bound)

Refuse negative inputs: the model is over natural numbers.
"""
function _check(reads::Integer, noise_bound::Integer)
    reads >= 0 || throw(DomainError(reads, "read counts are natural numbers"))
    noise_bound >= 0 || throw(DomainError(noise_bound, "the noise bound is a natural number"))
    return nothing
end
