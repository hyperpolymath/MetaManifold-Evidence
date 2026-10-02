{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

-- The two numbers a server reports, and how the verdict moves with the bound.
--
-- MetaManifold.Evidence.Counts states the fibre monus-free.  Here the interval
-- ends are functions, lo y n = y ∸ n and hi y n = y + n, and the fibre is
-- proved to be exactly the latents in [lo, hi].  So the two numbers a client
-- displays are proved, not merely computed.
--
-- The closed-form verdict is then characterised completely (VerdictView):
--
--   entailed   ⇔ n < y
--   refuted    ⇔ y = 0 and n = 0
--   unresolved ⇔ y ≤ n and n ≥ 1
--
-- and three facts about raising the noise bound follow:
--
--   * entailment survives lowering the bound (entailed-anti);
--   * unresolved survives raising it (unresolved-mono);
--   * refuted holds only at y = n = 0, and any positive bound turns it into
--     unresolved (refuted-fragile).
--
-- More noise never strengthens a verdict.

module MetaManifold.Evidence.Bounds where

open import Agda.Builtin.Bool using (true; false)
open import Agda.Builtin.Nat using (_-_; _<_)
open import ResidualEvidence.Prelude
open import ResidualEvidence.Core
open import ResidualEvidence.Finite.Row using (Verdict; entailed; refuted; unresolved; inconsistent)
open import MetaManifold.Evidence.Counts

------------------------------------------------------------------------
-- The interval ends

lo hi : Nat → Nat → Nat
lo y n = y - n
hi y n = y + n

-- Reads y are within n of x exactly when x is at least y ∸ n.
≤⇒lo : ∀ y n x → y ≤ x + n → lo y n ≤ x
≤⇒lo zero    zero    x p = z≤n
≤⇒lo zero    (suc n) x p = z≤n
≤⇒lo (suc y) zero    x p = subst (λ t → suc y ≤ t) (+-zero x) p
≤⇒lo (suc y) (suc n) x p = ≤⇒lo y n x (peel (subst (λ t → suc y ≤ t) (+-suc x n) p))
  where
  peel : ∀ {a b} → suc a ≤ suc b → a ≤ b
  peel (s≤s q) = q

lo⇒≤ : ∀ y n x → lo y n ≤ x → y ≤ x + n
lo⇒≤ zero    n       x p = z≤n
lo⇒≤ (suc y) zero    x p = subst (λ t → suc y ≤ t) (sym (+-zero x)) p
lo⇒≤ (suc y) (suc n) x p = subst (λ t → suc y ≤ t) (sym (+-suc x n)) (s≤s (lo⇒≤ y n x p))

-- The fibre over y is exactly the latents in [lo y n, hi y n].
InBounds : Nat → Nat → Nat → Set
InBounds y n x = (lo y n ≤ x) × (x ≤ hi y n)

fibre⇒bounds : ∀ {y n} (c : ReadFibre y n) → InBounds y n (latent (fst c))
fibre⇒bounds {y} {n} c with fibre⇒interval c
... | below , above = ≤⇒lo y n (latent (fst c)) below , above

bounds⇒fibre : ∀ {y n x} → InBounds y n x → Σ (ReadFibre y n) (λ c → latent (fst c) ≡ x)
bounds⇒fibre {y} {n} {x} (l , h) = interval⇒fibre (lo⇒≤ y n x l , h)

------------------------------------------------------------------------
-- A complete characterisation of the verdict

data VerdictView (y n : Nat) : Verdict → Set where
  v-entailed   : suc n ≤ y → VerdictView y n entailed
  v-refuted    : y ≡ zero → n ≡ zero → VerdictView y n refuted
  v-unresolved : y ≤ n → suc zero ≤ n → VerdictView y n unresolved

view : ∀ y n → VerdictView y n (verdict y n)
view y n with n < y in eq
... | true = v-entailed (<-true n y eq)
... | false with y
...   | zero with n
...     | zero  = v-refuted refl refl
...     | suc m = v-unresolved z≤n (s≤s z≤n)
view y n | false | suc k = v-unresolved y≤n (≤-trans (s≤s z≤n) y≤n)
  where
  y≤n : suc k ≤ n
  y≤n = <-false n (suc k) eq

-- The view at a verdict the function returned.
view-at : ∀ {y n v} → verdict y n ≡ v → VerdictView y n v
view-at {y} {n} h = subst (VerdictView y n) h (view y n)

------------------------------------------------------------------------
-- Moving the bound

private
  irrefl : ∀ k → suc k ≤ k → ⊥
  irrefl zero    ()
  irrefl (suc k) (s≤s p) = irrefl k p

  zero-not-suc : ∀ {k} → suc k ≤ zero → ⊥
  zero-not-suc ()

  ≤0 : ∀ {x} → x ≤ zero → x ≡ zero
  ≤0 z≤n = refl

  ⊥-elim : ∀ {A : Set} → ⊥ → A
  ⊥-elim ()

-- Lowering the noise bound keeps an entailment.
entailed-anti : ∀ {y n n'} → n' ≤ n → verdict y n ≡ entailed → verdict y n' ≡ entailed
entailed-anti {y} {n} {n'} n'≤n h with view-at h
... | v-entailed n<y with verdict y n' | view y n'
...   | entailed     | _ = refl
...   | refuted      | v-refuted y≡0 _ =
  ⊥-elim (zero-not-suc (subst (λ t → suc n ≤ t) y≡0 n<y))
...   | unresolved   | v-unresolved y≤n' _ =
  ⊥-elim (irrefl n (≤-trans n<y (≤-trans y≤n' n'≤n)))

-- Raising the noise bound keeps an unresolved verdict unresolved.
unresolved-mono : ∀ {y n n'} → n ≤ n' → verdict y n ≡ unresolved → verdict y n' ≡ unresolved
unresolved-mono {y} {n} {n'} n≤n' h with view-at h
... | v-unresolved y≤n 1≤n with verdict y n' | view y n'
...   | unresolved   | _ = refl
...   | entailed     | v-entailed n'<y =
  ⊥-elim (irrefl n' (≤-trans n'<y (≤-trans y≤n n≤n')))
...   | refuted      | v-refuted _ n'≡0 =
  ⊥-elim (zero-not-suc (subst (λ t → suc zero ≤ t) n'≡0 (≤-trans 1≤n n≤n')))

-- Refuted happens only at zero reads under zero noise.
refuted-only-at-zero : ∀ {y n} → verdict y n ≡ refuted → (y ≡ zero) × (n ≡ zero)
refuted-only-at-zero h with view-at h
... | v-refuted y≡0 n≡0 = y≡0 , n≡0

-- Any positive bound turns a refutation into unresolved.
refuted-fragile : ∀ {y n n'} → verdict y n ≡ refuted → suc zero ≤ n' →
  verdict y n' ≡ unresolved
refuted-fragile {y} {n} {n'} h 1≤n' with refuted-only-at-zero {y} {n} h
... | refl , _ with verdict zero n' | view zero n'
...   | unresolved | _ = refl
...   | entailed   | v-entailed ()
...   | refuted    | v-refuted _ n'≡0 =
  ⊥-elim (zero-not-suc (subst (λ t → suc zero ≤ t) n'≡0 1≤n'))

-- So more noise never strengthens a verdict: entailed at the larger bound
-- means entailed at the smaller, and refuted at the larger bound means the
-- bound is zero.
never-strengthens : ∀ {y n n'} → n ≤ n' →
  (verdict y n' ≡ entailed → verdict y n ≡ entailed) ×
  (verdict y n' ≡ refuted  → n' ≡ zero)
never-strengthens {y} {n} {n'} n≤n' =
  entailed-anti {y} {n'} {n} n≤n' , λ h → snd (refuted-only-at-zero {y} {n'} h)
