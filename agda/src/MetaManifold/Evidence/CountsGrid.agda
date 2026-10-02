{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell
--
-- The grid the Julia certificate is checked on: one row per read count and
-- noise bound in 0..k, holding the proved closed forms `verdict`, `lo`, `hi`.

module MetaManifold.Evidence.CountsGrid where

open import Agda.Builtin.List using (List; []; _∷_)
open import ResidualEvidence.Prelude
open import ResidualEvidence.Finite.Row using (Verdict)
open import MetaManifold.Evidence.Counts using (verdict)
open import MetaManifold.Evidence.Bounds using (lo; hi)

-- reads, noise bound, verdict, lower end, upper end
data Row : Set where
  row : Nat → Nat → Verdict → Nat → Nat → Row

-- The row Agda's closed forms give for `y` reads under bound `n`.
cell : Nat → Nat → Row
cell y n = row y n (verdict y n) (lo y n) (hi y n)

-- 0 ∷ 1 ∷ … ∷ k ∷ []
upto : Nat → List Nat
upto k = go k []
  where
  go : Nat → List Nat → List Nat
  go zero    acc = zero ∷ acc
  go (suc i) acc = go i (suc i ∷ acc)

-- Every pair, first component outermost, in the order Julia emits them.
cells : List Nat → List Nat → List Row
cells []       ns = []
cells (y ∷ ys) ns = along ns
  where
  along : List Nat → List Row
  along []       = cells ys ns
  along (n ∷ ms) = cell y n ∷ along ms

grid : Nat → List Row
grid k = cells (upto k) (upto k)
