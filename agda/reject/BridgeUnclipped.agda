{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
module BridgeUnclipped where
open import ResidualEvidence.Prelude
open import MetaManifold.Evidence.Bounds using (lo; hi)
open import MetaManifold.Evidence.CheckerBridge

-- Must fail: the cut-off at 6 in latents-agree cannot be dropped. With
-- y = 6 and n = 1 the counts interval is [5, 7], but the checker never
-- visits a latent above 6.
invalid : checkerLatents 6 1 ≡ span (lo 6 1) (hi 6 1)
invalid = refl
