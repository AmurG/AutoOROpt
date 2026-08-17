import Mathlib

namespace OpenROAD.ECP

open Classical
attribute [local instance] Classical.propDecidable

def clamp (x lo hi : Real) : Real := max lo (min hi x)

theorem clamp_mem (x lo hi : Real) (h : lo ≤ hi) :
    lo ≤ clamp x lo hi ∧ clamp x lo hi ≤ hi :=
  ⟨le_max_left _ _, max_le h (min_le_left _ _)⟩

theorem clamp_mono {x y lo hi : Real} (h : x ≤ y) : clamp x lo hi ≤ clamp y lo hi :=
  max_le_max le_rfl (min_le_min le_rfl h)

theorem clamp_eq_self {x lo hi : Real} (h0 : lo ≤ x) (h1 : x ≤ hi) : clamp x lo hi = x := by
  unfold clamp
  rw [min_eq_right h1, max_eq_right h0]

structure TimingParams where
  netWeightMax : Real
  netWeightExponent : Real
  useZeroSlackRef : Bool
  coveragePercent : Real
  useLengthFactor : Bool
  lengthAlpha : Real

def defaultParams : TimingParams :=
  { netWeightMax := 5, netWeightExponent := 1, useZeroSlackRef := true,
    coveragePercent := 0, useLengthFactor := false, lengthAlpha := 0.5 }

noncomputable def applyWeightMax (p : TimingParams) (v : Option Real) : TimingParams :=
  match v with
  | some x => if 0 < x then { p with netWeightMax := x } else p
  | none => p

noncomputable def applyWeightExp (p : TimingParams) (v : Option Real) : TimingParams :=
  match v with
  | some x => if 0 < x then { p with netWeightExponent := x } else p
  | none => p

noncomputable def applyCoverage (p : TimingParams) (v : Option Real) : TimingParams :=
  match v with
  | some x => if 0 < x ∧ x ≤ 100 then { p with coveragePercent := x } else p
  | none => p

noncomputable def applyLengthAlpha (p : TimingParams) (v : Option Real) : TimingParams :=
  match v with
  | some x => { p with lengthAlpha := clamp x 0 1 }
  | none => p

def applyBoolEnv (current : Bool) (raw : Option Int) : Bool :=
  match raw with
  | some n => decide (n ≠ 0)
  | none => current

theorem applyWeightMax_pos (p : TimingParams) (v : Option Real) (h : 0 < p.netWeightMax) :
    0 < (applyWeightMax p v).netWeightMax := by
  unfold applyWeightMax
  cases v with
  | none => exact h
  | some x =>
    dsimp only
    by_cases hx : 0 < x
    · rw [if_pos hx]; exact hx
    · rw [if_neg hx]; exact h

theorem applyWeightExp_pos (p : TimingParams) (v : Option Real) (h : 0 < p.netWeightExponent) :
    0 < (applyWeightExp p v).netWeightExponent := by
  unfold applyWeightExp
  cases v with
  | none => exact h
  | some x =>
    dsimp only
    by_cases hx : 0 < x
    · rw [if_pos hx]; exact hx
    · rw [if_neg hx]; exact h

theorem applyCoverage_mem (p : TimingParams) (v : Option Real)
    (h0 : 0 ≤ p.coveragePercent) (h1 : p.coveragePercent ≤ 100) :
    0 ≤ (applyCoverage p v).coveragePercent ∧ (applyCoverage p v).coveragePercent ≤ 100 := by
  unfold applyCoverage
  cases v with
  | none => exact ⟨h0, h1⟩
  | some x =>
    dsimp only
    by_cases hx : 0 < x ∧ x ≤ 100
    · rw [if_pos hx]; exact ⟨le_of_lt hx.1, hx.2⟩
    · rw [if_neg hx]; exact ⟨h0, h1⟩

theorem applyLengthAlpha_mem (p : TimingParams) (v : Option Real) :
    0 ≤ (applyLengthAlpha p v).lengthAlpha ∧ (applyLengthAlpha p v).lengthAlpha ≤ 1 ∨
      (applyLengthAlpha p v).lengthAlpha = p.lengthAlpha := by
  unfold applyLengthAlpha
  cases v with
  | none => exact Or.inr rfl
  | some x => exact Or.inl (clamp_mem x 0 1 (by norm_num))

theorem applyLengthAlpha_some_mem (p : TimingParams) (x : Real) :
    0 ≤ (applyLengthAlpha p (some x)).lengthAlpha ∧ (applyLengthAlpha p (some x)).lengthAlpha ≤ 1 := by
  unfold applyLengthAlpha; exact clamp_mem x 0 1 (by norm_num)

theorem applyBoolEnv_none (current : Bool) : applyBoolEnv current none = current := rfl

theorem defaultParams_ok :
    0 < defaultParams.netWeightMax ∧ 1 ≤ defaultParams.netWeightMax ∧
    0 < defaultParams.netWeightExponent ∧
    0 ≤ defaultParams.lengthAlpha ∧ defaultParams.lengthAlpha ≤ 1 ∧
    0 ≤ defaultParams.coveragePercent ∧ defaultParams.coveragePercent ≤ 100 := by
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_⟩ <;> norm_num [defaultParams]

noncomputable def coverageCount (worstCount : Nat) (cp : Real) : Nat :=
  if 2 ≤ worstCount then
    max 2 (max 1 (min worstCount ⌈(worstCount : Real) * cp / 100⌉₊))
  else
    max 1 (min worstCount ⌈(worstCount : Real) * cp / 100⌉₊)

theorem coverageCount_bounds (worstCount : Nat) (cp : Real) (h : 1 ≤ worstCount) :
    1 ≤ coverageCount worstCount cp ∧ coverageCount worstCount cp ≤ worstCount := by
  unfold coverageCount
  set raw := ⌈(worstCount : Real) * cp / 100⌉₊
  split_ifs with hge
  · refine ⟨le_trans (by norm_num) (le_max_left 2 _), ?_⟩
    have h1' : (1 : ℕ) ≤ worstCount := by omega
    exact max_le hge (max_le h1' (min_le_left _ _))
  · exact ⟨le_max_left _ _, max_le h (min_le_left _ _)⟩

theorem coverageCount_ge_two (worstCount : Nat) (cp : Real) (h : 2 ≤ worstCount) :
    2 ≤ coverageCount worstCount cp := by
  unfold coverageCount; rw [if_pos h]; exact le_max_left _ _

noncomputable def slackRef (useZeroRef : Bool) (coveragePercent slackMax cutoffSlack : Real)
    (worstEmpty : Bool) : Real :=
  if useZeroRef then
    if 0 < coveragePercent ∧ ¬ worstEmpty then min cutoffSlack 0 else 0
  else
    slackMax

theorem slackRef_nonpos (cp slackMax cutoff : Real) (we : Bool) :
    slackRef true cp slackMax cutoff we ≤ 0 := by
  unfold slackRef
  rw [if_pos rfl]
  split_ifs with h
  · exact min_le_right _ _
  · exact le_refl 0

theorem slackRef_no_coverage (slackMax cutoff : Real) (we : Bool) :
    slackRef true 0 slackMax cutoff we = 0 := by
  unfold slackRef; rw [if_pos rfl, if_neg]; rintro ⟨h, _⟩; exact (lt_irrefl _ h)

theorem slackRef_legacy (cp slackMax cutoff : Real) (we : Bool) :
    slackRef false cp slackMax cutoff we = slackMax := by
  unfold slackRef; rw [if_neg]; exact Bool.false_ne_true

noncomputable def lengthNorm (lengths : List Real) : Real :=
  if lengths = [] then 0 else lengths.sum / lengths.length

theorem lengthNorm_nonneg (lengths : List Real) (h : ∀ x ∈ lengths, 0 ≤ x) :
    0 ≤ lengthNorm lengths := by
  unfold lengthNorm
  split_ifs with he
  · exact le_refl 0
  · apply div_nonneg
    · exact List.sum_nonneg h
    · exact Nat.cast_nonneg _

def lengthFactor (alpha r : Real) : Real := (1 - alpha) + alpha * r

theorem lengthFactor_mem (alpha r : Real) (ha0 : 0 ≤ alpha) (ha1 : alpha ≤ 1)
    (hr0 : 0 ≤ r) (hr1 : r ≤ 1) :
    0 ≤ lengthFactor alpha r ∧ lengthFactor alpha r ≤ 1 := by
  unfold lengthFactor
  refine ⟨?_, ?_⟩
  · nlinarith [mul_nonneg ha0 hr0]
  · nlinarith [mul_nonneg ha0 (show (0 : Real) ≤ 1 - r by linarith)]

theorem lengthFactor_alpha_zero (r : Real) : lengthFactor 0 r = 1 := by
  unfold lengthFactor; ring

theorem lengthFactor_alpha_one (r : Real) : lengthFactor 1 r = r := by
  unfold lengthFactor; ring

theorem lengthFactor_mono_in_ratio (alpha r1 r2 : Real) (ha : 0 ≤ alpha) (h : r1 ≤ r2) :
    lengthFactor alpha r1 ≤ lengthFactor alpha r2 := by
  unfold lengthFactor; nlinarith [mul_le_mul_of_nonneg_left h ha]

theorem factor_mem (alpha lenRatio : Real) (applyLength : Bool) (ha0 : 0 ≤ alpha) (ha1 : alpha ≤ 1) :
    0 ≤ (if applyLength then lengthFactor alpha (clamp lenRatio 0 1) else 1) ∧
      (if applyLength then lengthFactor alpha (clamp lenRatio 0 1) else 1) ≤ 1 := by
  cases applyLength with
  | false => simp
  | true =>
    simp only [if_true]
    obtain ⟨hc0, hc1⟩ := clamp_mem lenRatio 0 1 (by norm_num)
    exact lengthFactor_mem alpha _ ha0 ha1 hc0 hc1

noncomputable def normalizedSlack (slackRef netSlack slackMin : Real) : Real :=
  clamp ((slackRef - netSlack) / (slackRef - slackMin)) 0 1

theorem normalizedSlack_mem (slackRef netSlack slackMin : Real) :
    0 ≤ normalizedSlack slackRef netSlack slackMin ∧
      normalizedSlack slackRef netSlack slackMin ≤ 1 := by
  unfold normalizedSlack; exact clamp_mem _ 0 1 (by norm_num)

noncomputable def timingWeight (p : TimingParams) (slackRef slackMin netSlack lenRatio : Real)
    (applyLength : Bool) : Real :=
  if netSlack < slackRef then
    if slackRef = slackMin then
      1
    else
      1 + (p.netWeightMax - 1) *
        ((normalizedSlack slackRef netSlack slackMin) ^ p.netWeightExponent *
          (if applyLength then lengthFactor p.lengthAlpha (clamp lenRatio 0 1) else 1))
  else
    1

theorem timingWeight_noncritical (p : TimingParams) (slackRef slackMin netSlack lenRatio : Real)
    (applyLength : Bool) (h : slackRef ≤ netSlack) :
    timingWeight p slackRef slackMin netSlack lenRatio applyLength = 1 := by
  unfold timingWeight; rw [if_neg (not_lt.mpr h)]

theorem timingWeight_degenerate (p : TimingParams) (slackRef slackMin netSlack lenRatio : Real)
    (applyLength : Bool) (h : slackRef = slackMin) :
    timingWeight p slackRef slackMin netSlack lenRatio applyLength = 1 := by
  unfold timingWeight
  by_cases h1 : netSlack < slackRef
  · rw [if_pos h1, if_pos h]
  · rw [if_neg h1]

theorem timingWeight_mem (p : TimingParams) (slackRef slackMin netSlack lenRatio : Real)
    (applyLength : Bool) (hexp : 0 ≤ p.netWeightExponent)
    (ha0 : 0 ≤ p.lengthAlpha) (ha1 : p.lengthAlpha ≤ 1) (hmax : 1 ≤ p.netWeightMax) :
    1 ≤ timingWeight p slackRef slackMin netSlack lenRatio applyLength ∧
      timingWeight p slackRef slackMin netSlack lenRatio applyLength ≤ p.netWeightMax := by
  unfold timingWeight
  by_cases h1 : netSlack < slackRef
  · rw [if_pos h1]
    by_cases h2 : slackRef = slackMin
    · rw [if_pos h2]; exact ⟨le_refl _, hmax⟩
    · rw [if_neg h2]
      obtain ⟨hn0, hn1⟩ := normalizedSlack_mem slackRef netSlack slackMin
      have hp0 : 0 ≤ (normalizedSlack slackRef netSlack slackMin) ^ p.netWeightExponent :=
        Real.rpow_nonneg hn0 _
      have hp1 : (normalizedSlack slackRef netSlack slackMin) ^ p.netWeightExponent ≤ 1 :=
        Real.rpow_le_one hn0 hn1 hexp
      obtain ⟨hf0, hf1⟩ := factor_mem p.lengthAlpha lenRatio applyLength ha0 ha1
      have hs0 : 0 ≤ (normalizedSlack slackRef netSlack slackMin) ^ p.netWeightExponent *
          (if applyLength then lengthFactor p.lengthAlpha (clamp lenRatio 0 1) else 1) :=
        mul_nonneg hp0 hf0
      have hs1 : (normalizedSlack slackRef netSlack slackMin) ^ p.netWeightExponent *
          (if applyLength then lengthFactor p.lengthAlpha (clamp lenRatio 0 1) else 1) ≤ 1 := by
        calc _ ≤ (1 : Real) * 1 := mul_le_mul hp1 hf1 hf0 (by norm_num)
          _ = 1 := by ring
      have hM : 0 ≤ p.netWeightMax - 1 := by linarith
      exact ⟨by nlinarith [mul_nonneg hM hs0], by nlinarith [mul_le_mul_of_nonneg_left hs1 hM]⟩
  · rw [if_neg h1]; exact ⟨le_refl _, hmax⟩

theorem timingWeight_antitone (p : TimingParams) (slackRef slackMin lenRatio : Real)
    (applyLength : Bool) (s1 s2 : Real)
    (hexp : 0 ≤ p.netWeightExponent) (ha0 : 0 ≤ p.lengthAlpha) (ha1 : p.lengthAlpha ≤ 1)
    (hmax : 1 ≤ p.netWeightMax) (hden : slackMin < slackRef) (h12 : s1 ≤ s2) (h2 : s2 < slackRef) :
    timingWeight p slackRef slackMin s2 lenRatio applyLength ≤
      timingWeight p slackRef slackMin s1 lenRatio applyLength := by
  have h1 : s1 < slackRef := lt_of_le_of_lt h12 h2
  have hne : slackRef ≠ slackMin := ne_of_gt hden
  unfold timingWeight
  rw [if_pos h2, if_pos h1, if_neg hne, if_neg hne]
  have hpos : 0 < slackRef - slackMin := by linarith
  have hratio : (slackRef - s2) / (slackRef - slackMin) ≤ (slackRef - s1) / (slackRef - slackMin) := by
    have := mul_le_mul_of_nonneg_right (show slackRef - s2 ≤ slackRef - s1 by linarith)
      (le_of_lt (inv_pos.mpr hpos))
    simpa [div_eq_mul_inv] using this
  have hnorm : normalizedSlack slackRef s2 slackMin ≤ normalizedSlack slackRef s1 slackMin := by
    unfold normalizedSlack; exact clamp_mono hratio
  have hn2 : 0 ≤ normalizedSlack slackRef s2 slackMin := (normalizedSlack_mem _ _ _).1
  have hrpow : (normalizedSlack slackRef s2 slackMin) ^ p.netWeightExponent ≤
      (normalizedSlack slackRef s1 slackMin) ^ p.netWeightExponent :=
    Real.rpow_le_rpow hn2 hnorm hexp
  obtain ⟨hf0, _⟩ := factor_mem p.lengthAlpha lenRatio applyLength ha0 ha1
  have hscaled : (normalizedSlack slackRef s2 slackMin) ^ p.netWeightExponent *
      (if applyLength then lengthFactor p.lengthAlpha (clamp lenRatio 0 1) else 1) ≤
      (normalizedSlack slackRef s1 slackMin) ^ p.netWeightExponent *
      (if applyLength then lengthFactor p.lengthAlpha (clamp lenRatio 0 1) else 1) :=
    mul_le_mul_of_nonneg_right hrpow hf0
  have hM : 0 ≤ p.netWeightMax - 1 := by linarith
  nlinarith [mul_le_mul_of_nonneg_left hscaled hM]

theorem timingWeight_linear (p : TimingParams) (slackRef slackMin netSlack lenRatio : Real)
    (hexp : p.netWeightExponent = 1) (h1 : netSlack < slackRef) (h2 : slackRef ≠ slackMin) :
    timingWeight p slackRef slackMin netSlack lenRatio false =
      1 + (p.netWeightMax - 1) * normalizedSlack slackRef netSlack slackMin := by
  unfold timingWeight
  rw [if_pos h1, if_neg h2, hexp, Real.rpow_one]
  simp

structure NetInfo where
  netSlack : Real
  lenRatio : Real

noncomputable def netWeightOf (p : TimingParams) (slackRef slackMin : Real) (applyLength : Bool)
    (n : NetInfo) : Real :=
  timingWeight p slackRef slackMin n.netSlack n.lenRatio applyLength

theorem weights_in_bounds (p : TimingParams) (slackRef slackMin : Real) (applyLength : Bool)
    (nets : List NetInfo) (hexp : 0 ≤ p.netWeightExponent)
    (ha0 : 0 ≤ p.lengthAlpha) (ha1 : p.lengthAlpha ≤ 1) (hmax : 1 ≤ p.netWeightMax) :
    ∀ w ∈ nets.map (netWeightOf p slackRef slackMin applyLength),
      1 ≤ w ∧ w ≤ p.netWeightMax := by
  intro w hw
  rw [List.mem_map] at hw
  obtain ⟨n, _, rfl⟩ := hw
  unfold netWeightOf
  exact timingWeight_mem p slackRef slackMin n.netSlack n.lenRatio applyLength hexp ha0 ha1 hmax

def resizeKept (overflow threshold : Real) : Prop := overflow < threshold

theorem resizeKept_mono (overflow t1 t2 : Real) (h : t1 ≤ t2) (hk : resizeKept overflow t1) :
    resizeKept overflow t2 := lt_of_lt_of_le hk h

theorem resizeKept_new_default (overflow : Real) (h : overflow < 1) : resizeKept overflow 1 := h

theorem newDefault_covers_old (overflow : Real) (hk : resizeKept overflow 0.3) :
    resizeKept overflow 1 :=
  resizeKept_mono overflow 0.3 1 (by norm_num) hk

def better (endIndex : Nat) (worstSlack prevWorstSlack endSlack prevEndSlack
    currTns prevCheckpointTns : Real) : Prop :=
  prevWorstSlack < worstSlack
  ∨ (prevWorstSlack ≤ worstSlack ∧ prevCheckpointTns < currTns)
  ∨ (endIndex ≠ 1 ∧ worstSlack = prevWorstSlack ∧ prevEndSlack < endSlack)

def oldBetter (endIndex : Nat) (worstSlack prevWorstSlack endSlack prevEndSlack : Real) : Prop :=
  prevWorstSlack < worstSlack
  ∨ (endIndex ≠ 1 ∧ worstSlack = prevWorstSlack ∧ prevEndSlack < endSlack)

theorem better_of_wns (endIndex : Nat) {worstSlack prevWorstSlack endSlack prevEndSlack
    currTns prevCheckpointTns : Real} (h : prevWorstSlack < worstSlack) :
    better endIndex worstSlack prevWorstSlack endSlack prevEndSlack currTns prevCheckpointTns :=
  Or.inl h

theorem better_of_tns (endIndex : Nat) {worstSlack prevWorstSlack endSlack prevEndSlack
    currTns prevCheckpointTns : Real}
    (hwns : prevWorstSlack ≤ worstSlack) (htns : prevCheckpointTns < currTns) :
    better endIndex worstSlack prevWorstSlack endSlack prevEndSlack currTns prevCheckpointTns :=
  Or.inr (Or.inl ⟨hwns, htns⟩)

theorem better_preserves_wns {endIndex : Nat} {worstSlack prevWorstSlack endSlack prevEndSlack
    currTns prevCheckpointTns : Real}
    (h : better endIndex worstSlack prevWorstSlack endSlack prevEndSlack currTns prevCheckpointTns) :
    prevWorstSlack ≤ worstSlack := by
  rcases h with h | h | h
  · exact le_of_lt h
  · exact h.1
  · exact le_of_eq h.2.1.symm

theorem oldBetter_imp_better (endIndex : Nat) (worstSlack prevWorstSlack endSlack prevEndSlack
    currTns prevCheckpointTns : Real)
    (h : oldBetter endIndex worstSlack prevWorstSlack endSlack prevEndSlack) :
    better endIndex worstSlack prevWorstSlack endSlack prevEndSlack currTns prevCheckpointTns := by
  rcases h with h | h
  · exact Or.inl h
  · exact Or.inr (Or.inr h)

structure LoopState where
  prevWorstSlack : Real
  prevEndSlack : Real
  prevCheckpointTns : Real
  decreasingPasses : Nat

structure Pass where
  worstSlack : Real
  endSlack : Real
  currTns : Real
  endIndex : Nat

noncomputable def stepPass (s : LoopState) (p : Pass) : LoopState :=
  if better p.endIndex p.worstSlack s.prevWorstSlack p.endSlack s.prevEndSlack
      p.currTns s.prevCheckpointTns then
    { prevWorstSlack := p.worstSlack, prevEndSlack := p.endSlack,
      prevCheckpointTns := p.currTns, decreasingPasses := 0 }
  else
    { s with decreasingPasses := s.decreasingPasses + 1 }

theorem stepPass_accepts_resets (s : LoopState) (p : Pass)
    (h : better p.endIndex p.worstSlack s.prevWorstSlack p.endSlack s.prevEndSlack
      p.currTns s.prevCheckpointTns) :
    (stepPass s p).decreasingPasses = 0 := by
  unfold stepPass; rw [if_pos h]

theorem stepPass_rejects_increments (s : LoopState) (p : Pass)
    (h : ¬ better p.endIndex p.worstSlack s.prevWorstSlack p.endSlack s.prevEndSlack
      p.currTns s.prevCheckpointTns) :
    (stepPass s p).decreasingPasses = s.decreasingPasses + 1 ∧
      (stepPass s p).prevWorstSlack = s.prevWorstSlack := by
  unfold stepPass; rw [if_neg h]; exact ⟨rfl, rfl⟩

theorem stepPass_wns_mono (s : LoopState) (p : Pass) :
    s.prevWorstSlack ≤ (stepPass s p).prevWorstSlack := by
  unfold stepPass
  by_cases h : better p.endIndex p.worstSlack s.prevWorstSlack p.endSlack s.prevEndSlack
      p.currTns s.prevCheckpointTns
  · rw [if_pos h]; exact better_preserves_wns h
  · rw [if_neg h]

theorem repairLoop_wns_mono (s0 : LoopState) (passes : List Pass) :
    s0.prevWorstSlack ≤ (passes.foldl stepPass s0).prevWorstSlack := by
  induction passes generalizing s0 with
  | nil => simp
  | cons p ps ih =>
    simp only [List.foldl_cons]
    exact le_trans (stepPass_wns_mono s0 p) (ih (stepPass s0 p))

def applyDecrMaxPasses (dflt : Nat) (parsed : Option Nat) : Nat :=
  match parsed with
  | some n => if 0 < n ∧ n ≤ 2147483647 then n else dflt
  | none => dflt

theorem applyDecrMaxPasses_pos (dflt : Nat) (parsed : Option Nat) (h : 0 < dflt) :
    0 < applyDecrMaxPasses dflt parsed := by
  unfold applyDecrMaxPasses
  cases parsed with
  | none => exact h
  | some n =>
    dsimp only
    by_cases hn : 0 < n ∧ n ≤ 2147483647
    · rw [if_pos hn]; exact hn.1
    · rw [if_neg hn]; exact h

theorem applyDecrMaxPasses_default : applyDecrMaxPasses 50 none = 50 := rfl

variable {α : Type*}

def passesOptionalFilters (matchFootprint footprintsMatch userFnFilter userFnMatch : Bool) : Bool :=
  (!matchFootprint || footprintsMatch) && (!userFnFilter || userFnMatch)

noncomputable def swappableResult (filtered candidate : List α) : List α :=
  if filtered = [] then candidate else filtered

def fellBack (filtered candidate : List α) (filtersRequested : Bool) : Prop :=
  filtered = [] ∧ filtersRequested = true ∧ candidate ≠ []

theorem swappableResult_nonempty (filtered candidate : List α) (hc : candidate ≠ []) :
    swappableResult filtered candidate ≠ [] := by
  unfold swappableResult
  by_cases h : filtered = []
  · rw [if_pos h]; exact hc
  · rw [if_neg h]; exact h

theorem swappableResult_subset (filtered candidate : List α) (hsub : filtered ⊆ candidate) :
    swappableResult filtered candidate ⊆ candidate := by
  unfold swappableResult
  by_cases h : filtered = []
  · rw [if_pos h]; exact fun _ hx => hx
  · rw [if_neg h]; exact hsub

theorem swappableResult_filter_subset (candidate : List α) (pred : α → Bool) :
    swappableResult (candidate.filter pred) candidate ⊆ candidate :=
  swappableResult_subset _ _ (List.filter_subset' _)

theorem no_fallback_when_filtered (filtered candidate : List α) (fr : Bool) (h : filtered ≠ []) :
    ¬ fellBack filtered candidate fr := by
  rintro ⟨h1, _, _⟩; exact h h1

theorem fellBack_returns_candidate (filtered candidate : List α) (fr : Bool)
    (h : fellBack filtered candidate fr) :
    swappableResult filtered candidate = candidate ∧ filtered = [] := by
  obtain ⟨h1, _, _⟩ := h
  refine ⟨?_, h1⟩
  unfold swappableResult; rw [if_pos h1]

theorem no_fallback_no_filters (filtered candidate : List α)
    (h : fellBack filtered candidate false) : False := by
  obtain ⟨_, h2, _⟩ := h; exact Bool.false_ne_true h2

theorem swappableResult_all_pass (candidate : List α) (pred : α → Bool)
    (hall : ∀ x ∈ candidate, pred x = true) :
    swappableResult (candidate.filter pred) candidate = candidate := by
  rw [List.filter_eq_self.mpr hall]
  unfold swappableResult
  by_cases h : candidate = []
  · rw [if_pos h, h]
  · rw [if_neg h]

def runEliminateDeadLogic {β : Type*} (enabled : Bool) (netlist : β) (elim : β → β) : β :=
  if enabled then elim netlist else netlist

theorem eliminateDeadLogic_disabled_noop {β : Type*} (netlist : β) (elim : β → β) :
    runEliminateDeadLogic false netlist elim = netlist := by
  simp [runEliminateDeadLogic]

theorem eliminateDeadLogic_enabled_runs {β : Type*} (netlist : β) (elim : β → β) :
    runEliminateDeadLogic true netlist elim = elim netlist := by
  simp [runEliminateDeadLogic]

end OpenROAD.ECP
