{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
module EntailedAtBound where
open import ResidualEvidence.Prelude
open import ResidualEvidence.Core
open import MetaManifold.Evidence.Counts

-- Must fail: with y = n = 2 a zero latent is admissible, so presence is not
-- entailed; the premise n < y does not hold.
invalid : Holds (case 2 2) Present
invalid = entailed-sound (s≤s (s≤s z≤n))
