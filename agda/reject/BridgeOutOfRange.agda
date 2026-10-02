{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
module BridgeOutOfRange where
open import ResidualEvidence.Prelude
open import ResidualEvidence.Finite.Checker using (presence)
open import MetaManifold.Evidence.Counts using (verdict)
open import MetaManifold.Evidence.CheckerBridge

-- Must fail: the range premise of presence-agrees cannot be dropped. With
-- y = 7 and n = 0 the checker has no candidate inside −6..6 (inconsistent),
-- while the counts verdict is entailed.
invalid : presence (asConfig 7 0) ≡ verdict 7 0
invalid = refl
