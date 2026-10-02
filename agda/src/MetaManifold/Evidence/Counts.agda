{-# OPTIONS --safe --without-K #-}
-- SPDX-License-Identifier: AGPL-3.0-or-later
-- SPDX-FileCopyrightText: 2026 Jonathan D.A. Jewell

-- Read counts as residual evidence.
--
-- A world pairs a latent abundance with an observed read count that differs
-- from it by some noise d, in either direction.  Evidence bounds the noise by
-- n.  The generic semantics (Candidate, Case, Holds) come from
-- residual-evidence-types; this module instantiates them for counts and proves
--
--   * the candidate latents for observation y are exactly the integers x with
--     y ≤ x + n and x ≤ y + n (the interval [y ∸ n, y + n], stated monus-free),
--     so a fibre is two numbers, never a list to enumerate;
--   * every case is inhabited, so counts never yield `inconsistent`;
--   * the closed-form presence verdict is sound for every constructor it
--     returns.
--
-- Assumption to confirm with the data owner: the noise bound is an absolute
-- number of reads, and latent abundance is a natural number.

module MetaManifold.Evidence.Counts where

open import Agda.Builtin.Bool using (Bool; true; false)
open import Agda.Builtin.Nat using (_<_)
open import ResidualEvidence.Prelude
open import ResidualEvidence.Core
open import ResidualEvidence.Finite.Row using (Verdict; entailed; refuted; unresolved; inconsistent)

------------------------------------------------------------------------
-- Arithmetic on builtin naturals (no standard library)

data _⊎_ {a b} (A : Set a) (B : Set b) : Set (a ⊔ b) where
  inj₁ : A → A ⊎ B
  inj₂ : B → A ⊎ B

≤-refl : ∀ {n} → n ≤ n
≤-refl {zero}  = z≤n
≤-refl {suc n} = s≤s ≤-refl

≤-trans : ∀ {a b c} → a ≤ b → b ≤ c → a ≤ c
≤-trans z≤n       _         = z≤n
≤-trans (s≤s p) (s≤s q) = s≤s (≤-trans p q)

≤-total : ∀ a b → (a ≤ b) ⊎ (b ≤ a)
≤-total zero    b       = inj₁ z≤n
≤-total (suc a) zero    = inj₂ z≤n
≤-total (suc a) (suc b) with ≤-total a b
... | inj₁ p = inj₁ (s≤s p)
... | inj₂ p = inj₂ (s≤s p)

≤-+ʳ : ∀ m k → m ≤ m + k
≤-+ʳ zero    k = z≤n
≤-+ʳ (suc m) k = s≤s (≤-+ʳ m k)

+-monoʳ : ∀ m {a b} → a ≤ b → m + a ≤ m + b
+-monoʳ zero    p = p
+-monoʳ (suc m) p = s≤s (+-monoʳ m p)

+-cancelʳ : ∀ m {a b} → m + a ≤ m + b → a ≤ b
+-cancelʳ zero    p       = p
+-cancelʳ (suc m) (s≤s p) = +-cancelʳ m p

+-assoc : ∀ a b c → (a + b) + c ≡ a + (b + c)
+-assoc zero    b c = refl
+-assoc (suc a) b c = cong suc (+-assoc a b c)

+-zero : ∀ a → a + zero ≡ a
+-zero zero    = refl
+-zero (suc a) = cong suc (+-zero a)

+-suc : ∀ a b → a + suc b ≡ suc (a + b)
+-suc zero    b = refl
+-suc (suc a) b = cong suc (+-suc a b)

+-comm : ∀ a b → a + b ≡ b + a
+-comm zero    b = sym (+-zero b)
+-comm (suc a) b = trans (cong suc (+-comm a b)) (sym (+-suc b a))

subst : ∀ {a p} {A : Set a} (P : A → Set p) {x y} → x ≡ y → P x → P y
subst P refl px = px

-- m ≤ n gives the difference as a witness.
≤-diff : ∀ {m n} → m ≤ n → Σ Nat (λ k → m + k ≡ n)
≤-diff {zero} {n} z≤n = n , refl
≤-diff (s≤s p) with ≤-diff p
... | k , eq = k , cong suc eq

-- Bridge from the builtin Boolean comparison to the inductive order.
<-true : ∀ a b → (a < b) ≡ true → suc a ≤ b
<-true zero    (suc b) refl = s≤s z≤n
<-true (suc a) (suc b) eq   = s≤s (<-true a b eq)
<-true _       zero    ()

<-false : ∀ a b → (a < b) ≡ false → b ≤ a
<-false a       zero    _  = z≤n
<-false zero    (suc b) ()
<-false (suc a) (suc b) eq = s≤s (<-false a b eq)

------------------------------------------------------------------------
-- Worlds, observation, evidence

-- `over`: the reads exceed the latent by d.  `under`: the latent exceeds the
-- reads by d.  The base is the smaller of the two quantities in both cases.
data Direction : Set where
  over under : Direction

record World : Set where
  constructor world
  field
    base  : Nat
    noise : Nat
    dir   : Direction
open World public

latent : World → Nat
latent (world b d over)  = b
latent (world b d under) = b + d

observed : World → Nat
observed (world b d over)  = b + d
observed (world b d under) = b

-- Evidence: the noise is within the bound n (in reads).
Bounded : Nat → World → Set
Bounded n w = noise w ≤ n

-- The fibre over observation y under noise bound n.
ReadFibre : Nat → Nat → Set
ReadFibre y n = Candidate observed y (Bounded n)

Present Absent : World → Set
Present w = ¬ (latent w ≡ zero)
Absent  w = latent w ≡ zero

------------------------------------------------------------------------
-- Every case is inhabited: the noiseless world.

noiseless : ∀ y n → ReadFibre y n
noiseless y n = world y zero under , refl , z≤n

case : ∀ y n → Case observed y (Bounded n)
case y n = inhabited (noiseless y n)

------------------------------------------------------------------------
-- The fibre is the interval: y ≤ x + n and x ≤ y + n.

InInterval : Nat → Nat → Nat → Set
InInterval y n x = (y ≤ x + n) × (x ≤ y + n)

fibre⇒interval : ∀ {y n} (c : ReadFibre y n) → InInterval y n (latent (fst c))
fibre⇒interval {y} {n} (world b d over , refl , d≤n) =
  -- y = b + d, latent = b
  +-monoʳ b d≤n , ≤-trans (≤-+ʳ b d) (≤-+ʳ (b + d) n)
fibre⇒interval {y} {n} (world b d under , refl , d≤n) =
  -- y = b, latent = b + d
  subst (λ t → b ≤ t) (sym (+-assoc b d n)) (≤-+ʳ b (d + n)) , +-monoʳ b d≤n

interval⇒fibre : ∀ {y n x} → InInterval y n x →
  Σ (ReadFibre y n) (λ c → latent (fst c) ≡ x)
interval⇒fibre {y} {n} {x} (lo , hi) with ≤-total x y
... | inj₁ x≤y with ≤-diff x≤y
...   | d , x+d≡y =
  -- reads over latent by d; d ≤ n because x + d = y ≤ x + n
  (world x d over , x+d≡y , +-cancelʳ x (subst (λ t → t ≤ x + n) (sym x+d≡y) lo)) , refl
interval⇒fibre {y} {n} {x} (lo , hi) | inj₂ y≤x with ≤-diff y≤x
...   | d , y+d≡x =
  (world y d under , refl , +-cancelʳ y (subst (λ t → t ≤ y + n) (sym y+d≡x) hi)) , y+d≡x

------------------------------------------------------------------------
-- Closed-form presence verdict and its soundness

verdict : Nat → Nat → Verdict
verdict y n with n < y
... | true  = entailed
... | false with y
...   | zero  with n
...     | zero  = refuted
...     | suc _ = unresolved
verdict y n | false | suc _ = unresolved

-- n < y: every candidate latent is at least y − n ≥ 1.
entailed-sound : ∀ {y n} → suc n ≤ y → Holds (case y n) Present
entailed-sound {y} {n} n<y c latent≡0 with fibre⇒interval c
... | lo , _ = absurd (≤-trans n<y (subst (λ t → y ≤ t + n) latent≡0 lo))
  where
  absurd : suc n ≤ n → ⊥
  absurd = go n
    where
    go : ∀ k → suc k ≤ k → ⊥
    go zero    ()
    go (suc k) (s≤s p) = go k p

-- y = n = 0: the only candidate latent is 0.
refuted-sound : Holds (case zero zero) Absent
refuted-sound c with fibre⇒interval c
... | _ , hi = le0 hi
  where
  le0 : ∀ {x} → x ≤ zero → x ≡ zero
  le0 z≤n = refl

-- y ≤ n with y + n > 0: latent 0 and latent y + n are both candidates.
unresolved-sound : ∀ {y n} → y ≤ n → ¬ (y + n ≡ zero) →
  (¬ Holds (case y n) Present) × (¬ Holds (case y n) Absent)
unresolved-sound {y} {n} y≤n nonzero =
  (λ h → h zero-candidate refl) , (λ h → nonzero (h top-candidate))
  where
  zero-candidate : ReadFibre y n
  zero-candidate = world zero y over , refl , y≤n
  top-candidate : ReadFibre y n
  top-candidate = world y n under , refl , ≤-refl

-- The verdict function is sound for every constructor it can return.
data Sound (y n : Nat) : Verdict → Set where
  is-entailed   : Holds (case y n) Present → Sound y n entailed
  is-refuted    : Holds (case y n) Absent  → Sound y n refuted
  is-unresolved : ¬ Holds (case y n) Present → ¬ Holds (case y n) Absent →
                  Sound y n unresolved

verdict-sound : ∀ y n → Sound y n (verdict y n)
verdict-sound y n with n < y in eq
... | true = is-entailed (entailed-sound (<-true n y eq))
... | false with y
...   | zero with n
...     | zero  = is-refuted refuted-sound
...     | suc m =
  let p = unresolved-sound {zero} {suc m} z≤n (λ ()) in is-unresolved (fst p) (snd p)
verdict-sound y n | false | suc k =
  let p = unresolved-sound {suc k} {n} (<-false n (suc k) eq) (λ ())
  in is-unresolved (fst p) (snd p)

-- Counts never produce `inconsistent`.
never-inconsistent : ∀ y n → ¬ (verdict y n ≡ inconsistent)
never-inconsistent y n eq with verdict y n | verdict-sound y n
never-inconsistent y n () | entailed     | _
never-inconsistent y n () | refuted      | _
never-inconsistent y n () | unresolved   | _
