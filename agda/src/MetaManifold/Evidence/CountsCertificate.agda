{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
--
-- The Julia verdict code agrees with the proved closed forms on every read
-- count and noise bound in 0..12. `expected` is generated from
-- MetaManifoldEvidence.count_verdict and fibre; `grid 12` is computed here
-- from `verdict`, `lo` and `hi`. Certified on the grid; the closed forms are
-- proved for all naturals in Counts.agda and Bounds.agda.

module MetaManifold.Evidence.CountsCertificate where

open import ResidualEvidence.Prelude
open import MetaManifold.Evidence.CountsGrid using (grid)
open import MetaManifold.Evidence.CountsJuliaTable using (expected)

julia-agrees : grid 12 ≡ expected
julia-agrees = refl
