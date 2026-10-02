{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
module RefutedUnderNoise where
open import ResidualEvidence.Prelude
open import ResidualEvidence.Core
open import MetaManifold.Evidence.Counts

-- Must fail: zero reads with noise bound 1 admit latent 1, so absence is not
-- established; refuted-sound covers only y = n = 0.
invalid : Holds (case 0 1) Absent
invalid = refuted-sound
