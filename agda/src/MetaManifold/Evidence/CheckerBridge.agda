{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
--
-- The counts model against the certified finite checker of
-- residual-evidence-types (ResidualEvidence.Finite.Checker, the explorer's
-- model 'signed-integer-v1').
--
-- The two models differ. The checker's worlds are integer (latent, noise)
-- pairs confined to −6..6, so it also admits negative latents. Counts
-- worlds are natural latents with no range limit. They meet on residual
-- y ∈ 0..6 and noise bound n ∈ 0..6, under the exact view with no
-- assumption on the latent. On that whole shared domain this module proves
-- that
--
--   * the checker's presence verdict is the counts `verdict y n`
--     (`presence-agrees`), even though the checker also sees negative
--     latents; and
--   * the natural latents among the checker's candidates are exactly the
--     counts interval [lo, hi], cut off at the checker's edge 6
--     (`latents-agree`).
--
-- The domain is finite because the checker is. Each case is decided by
-- normalisation. agda/reject/BridgeOutOfRange and agda/reject/BridgeUnclipped
-- show the range premise and the cut-off cannot be dropped.

module MetaManifold.Evidence.CheckerBridge where

open import Agda.Builtin.Bool using (false; true)
open import Agda.Builtin.Int using (Int; pos; negsuc)
open import Agda.Builtin.List using (List; []; _∷_)
open import Agda.Builtin.Nat using (_-_; _<_)
open import ResidualEvidence.Prelude
open import ResidualEvidence.Finite.Row using (exact)
open import ResidualEvidence.Finite.Checker using (Config; config; presence; enumerate; latents)
open import MetaManifold.Evidence.Counts using (verdict)
open import MetaManifold.Evidence.Bounds using (lo; hi)

-- The checker configuration for y observed reads under noise bound n.
asConfig : Nat → Nat → Config
asConfig y n = config (pos y) n exact false

-- The non-negative entries of a list of integers, as naturals, in order.
naturals : List Int → List Nat
naturals [] = []
naturals (pos k ∷ xs) = k ∷ naturals xs
naturals (negsuc _ ∷ xs) = naturals xs

-- lo, lo + 1, …, hi; empty when hi < lo.
span : Nat → Nat → List Nat
span a b = from a (suc b - a)
  where
  from : Nat → Nat → List Nat
  from x zero = []
  from x (suc k) = x ∷ from (suc x) k

-- The smaller of two naturals.
min : Nat → Nat → Nat
min a b with a < b
... | true = a
... | false = b

-- The checker's natural latents for a counts cell.
checkerLatents : Nat → Nat → List Nat
checkerLatents y n = naturals (latents (enumerate (asConfig y n)))

-- A property of every k ≤ 6 follows from its seven instances.
upto6 : ∀ {p} (P : Nat → Set p) →
  P 0 → P 1 → P 2 → P 3 → P 4 → P 5 → P 6 → ∀ {k} → k ≤ 6 → P k
upto6 P p0 p1 p2 p3 p4 p5 p6 z≤n = p0
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s z≤n) = p1
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s (s≤s z≤n)) = p2
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s (s≤s (s≤s z≤n))) = p3
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s (s≤s (s≤s (s≤s z≤n)))) = p4
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s (s≤s (s≤s (s≤s (s≤s z≤n))))) = p5
upto6 P p0 p1 p2 p3 p4 p5 p6 (s≤s (s≤s (s≤s (s≤s (s≤s (s≤s z≤n)))))) = p6

-- The checker's presence verdict is the counts verdict on the shared domain.
PresenceAgrees : Nat → Nat → Set
PresenceAgrees y n = presence (asConfig y n) ≡ verdict y n

presence-agrees : ∀ {y n} → y ≤ 6 → n ≤ 6 → PresenceAgrees y n
presence-agrees {y} {n} py = upto6 (λ y → ∀ {n} → n ≤ 6 → PresenceAgrees y n)
  (upto6 (PresenceAgrees 0) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 1) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 2) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 3) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 4) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 5) refl refl refl refl refl refl refl)
  (upto6 (PresenceAgrees 6) refl refl refl refl refl refl refl)
  py

-- The checker's natural latents are the counts interval, cut off at 6.
LatentsAgree : Nat → Nat → Set
LatentsAgree y n = checkerLatents y n ≡ span (lo y n) (min (hi y n) 6)

latents-agree : ∀ {y n} → y ≤ 6 → n ≤ 6 → LatentsAgree y n
latents-agree {y} {n} py = upto6 (λ y → ∀ {n} → n ≤ 6 → LatentsAgree y n)
  (upto6 (LatentsAgree 0) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 1) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 2) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 3) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 4) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 5) refl refl refl refl refl refl refl)
  (upto6 (LatentsAgree 6) refl refl refl refl refl refl refl)
  py
