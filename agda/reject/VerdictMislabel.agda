{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
module VerdictMislabel where
open import ResidualEvidence.Prelude
open import ResidualEvidence.Finite.Row using (Verdict; entailed; unresolved)
open import MetaManifold.Evidence.Counts

-- Must fail: 3 reads with noise bound 1 is entailed, not unresolved.
invalid : verdict 3 1 ≡ unresolved
invalid = refl
