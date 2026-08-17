import Mathlib

namespace OpenROAD.WL

noncomputable section

structure GlobalSwapParams where
  passes : Int
  tolerance : Real
  tradeoff : Real
  profiling_excess : Real
  budget_multipliers : List Real
  area_weight : Real
  pin_weight : Real
  user_congestion_weight : Real
  sampling_moves : Int
  normalization_interval : Int

def defaultParams : GlobalSwapParams where
  passes := 2
  tolerance := 0.01
  tradeoff := 0.4
  profiling_excess := 1.10
  budget_multipliers := [1.50, 1.25, 1.10, 1.04]
  area_weight := 0.4
  pin_weight := 0.6
  user_congestion_weight := 35.0
  sampling_moves := 150
  normalization_interval := 1000

def resetParams (_ : GlobalSwapParams) : GlobalSwapParams := defaultParams

def clamp01 (t : Real) : Real := max 0 (min 1 t)

theorem clamp01_mem (t : Real) : 0 ≤ clamp01 t ∧ clamp01 t ≤ 1 :=
  ⟨le_max_left _ _, max_le (by norm_num) (min_le_left _ _)⟩

theorem clamp01_mono {x y : Real} (h : x ≤ y) : clamp01 x ≤ clamp01 y :=
  max_le_max le_rfl (min_le_min le_rfl h)

theorem clamp01_id {t : Real} (h0 : 0 ≤ t) (h1 : t ≤ 1) : clamp01 t = t := by
  unfold clamp01; rw [min_eq_right h1, max_eq_right h0]

theorem clamp01_zero : clamp01 0 = 0 := by norm_num [clamp01]
theorem clamp01_one : clamp01 1 = 1 := by norm_num [clamp01]

def cfgPasses (p : GlobalSwapParams) (v : Int) : GlobalSwapParams :=
  if v > 0 then { p with passes := v } else p
def cfgTolerance (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v > 0 then { p with tolerance := v } else p
def cfgTradeoff (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v ≥ 0 then { p with tradeoff := clamp01 v } else p
def cfgAreaWeight (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v ≥ 0 then { p with area_weight := v } else p
def cfgPinWeight (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v ≥ 0 then { p with pin_weight := v } else p
def cfgUserWeight (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v > 0 then { p with user_congestion_weight := v } else p
def cfgSampling (p : GlobalSwapParams) (v : Int) : GlobalSwapParams :=
  if v > 0 then { p with sampling_moves := v } else p
def cfgNormalization (p : GlobalSwapParams) (v : Int) : GlobalSwapParams :=
  if v > 0 then { p with normalization_interval := v } else p
def cfgProfilingExcess (p : GlobalSwapParams) (v : Real) : GlobalSwapParams :=
  if v > 0 then { p with profiling_excess := v } else p

def budgetMultipliersOrDefault (l : List Real) : List Real :=
  if l = [] then [1.0] else l

theorem budgetMultipliersOrDefault_ne_nil (l : List Real) :
    budgetMultipliersOrDefault l ≠ [] := by
  unfold budgetMultipliersOrDefault
  by_cases h : l = [] <;> simp [h]

def cfgBudget (p : GlobalSwapParams) (l : List Real) : GlobalSwapParams :=
  let p1 := if l = [] then p else { p with budget_multipliers := l }
  { p1 with budget_multipliers := budgetMultipliersOrDefault p1.budget_multipliers }

theorem cfgBudget_ne_nil (p : GlobalSwapParams) (l : List Real) :
    (cfgBudget p l).budget_multipliers ≠ [] := by
  unfold cfgBudget
  simp only
  exact budgetMultipliersOrDefault_ne_nil _

def configure (p : GlobalSwapParams)
    (passes : Int) (tolerance tradeoff area_weight pin_weight user_weight : Real)
    (sampling normalization : Int) (profiling_excess : Real)
    (budget_multipliers : List Real) : GlobalSwapParams :=
  cfgBudget
    (cfgProfilingExcess
      (cfgNormalization
        (cfgSampling
          (cfgUserWeight
            (cfgPinWeight
              (cfgAreaWeight
                (cfgTradeoff
                  (cfgTolerance
                    (cfgPasses p passes) tolerance) tradeoff)
                area_weight) pin_weight) user_weight) sampling) normalization)
      profiling_excess)
    budget_multipliers

def weightsValid (p : GlobalSwapParams) : Prop :=
  0 ≤ p.area_weight ∧ 0 ≤ p.pin_weight ∧ (p.area_weight ≠ 0 ∨ p.pin_weight ≠ 0)

theorem default_weightsValid : weightsValid defaultParams := by
  refine ⟨by norm_num [defaultParams], by norm_num [defaultParams], ?_⟩
  left; norm_num [defaultParams]

theorem cfgTradeoff_mem (p : GlobalSwapParams) (v : Real)
    (h : 0 ≤ p.tradeoff ∧ p.tradeoff ≤ 1) :
    0 ≤ (cfgTradeoff p v).tradeoff ∧ (cfgTradeoff p v).tradeoff ≤ 1 := by
  unfold cfgTradeoff
  by_cases hv : v ≥ 0
  · rw [if_pos hv]; exact clamp01_mem v
  · rw [if_neg hv]; exact h

theorem configure_budget_ne_nil (p : GlobalSwapParams)
    (passes : Int) (tolerance tradeoff area_weight pin_weight user_weight : Real)
    (sampling normalization : Int) (profiling_excess : Real) (bm : List Real) :
    (configure p passes tolerance tradeoff area_weight pin_weight user_weight
      sampling normalization profiling_excess bm).budget_multipliers ≠ [] :=
  cfgBudget_ne_nil _ _

def passesRun (p : Int) : Int := max p 1

def tolRun (t : Real) : Real := max t 0.01

def tradeoffRun (t : Real) : Real := clamp01 t

theorem passesRun_ge_one (p : Int) : 1 ≤ passesRun p := le_max_right _ _
theorem tolRun_ge (t : Real) : 0.01 ≤ tolRun t := le_max_right _ _
theorem tradeoffRun_mem (t : Real) :
    0 ≤ tradeoffRun t ∧ tradeoffRun t ≤ 1 := clamp01_mem t

def wlThreshold (tradeoff : Real) : Int := ⌊tradeoff * 1000⌋

def triesWLMove (r : Int) (tradeoff : Real) : Prop := wlThreshold tradeoff ≤ r

theorem triesWL_of_tradeoff_zero {r : Int} (h : 0 ≤ r) : triesWLMove r 0 := by
  unfold triesWLMove wlThreshold
  simp only [zero_mul, Int.floor_zero]
  exact h

theorem not_triesWL_of_tradeoff_ge_one {r : Int} (hr : r < 1000) {tradeoff : Real}
    (ht : 1 ≤ tradeoff) : ¬ triesWLMove r tradeoff := by
  unfold triesWLMove wlThreshold
  have h1000 : (1000 : Int) ≤ ⌊tradeoff * 1000⌋ := by
    rw [Int.le_floor]; push_cast; nlinarith
  intro hcontra
  omega

def generateMove (triesWL wlSucc randSucc : Bool) : Bool :=
  let mg := if triesWL then wlSucc else false
  if mg then true else randSucc

theorem generateMove_spec (tw ws rs : Bool) :
    generateMove tw ws rs = ((tw && ws) || rs) := by
  cases tw <;> cases ws <;> cases rs <;> rfl

theorem generateMove_no_wl (ws rs : Bool) : generateMove false ws rs = rs := by
  simp [generateMove_spec]

def perPixel (total count scale : Real) : Real := (total / count) * scale

def clampNonneg (v : Real) : Real := max 0 v

theorem clampNonneg_nonneg (v : Real) : 0 ≤ clampNonneg v := le_max_left _ _
theorem clampNonneg_id {v : Real} (h : 0 ≤ v) : clampNonneg v = v := max_eq_right h

def congContribution (areaW pinW cellArea numPins : Real) : Real :=
  areaW * cellArea + pinW * numPins

theorem congContribution_nonneg {areaW pinW cellArea numPins : Real}
    (h1 : 0 ≤ areaW) (h2 : 0 ≤ pinW) (h3 : 0 ≤ cellArea) (h4 : 0 ≤ numPins) :
    0 ≤ congContribution areaW pinW cellArea numPins :=
  add_nonneg (mul_nonneg h1 h3) (mul_nonneg h2 h4)

def weightedDensity (area pins maxArea maxPins areaW pinW : Real) : Real :=
  areaW * (area / maxArea) + pinW * (pins / maxPins)

theorem weightedDensity_nonneg {area pins maxArea maxPins areaW pinW : Real}
    (ha : 0 ≤ area) (hp : 0 ≤ pins) (hma : 0 < maxArea) (hmp : 0 < maxPins)
    (haw : 0 ≤ areaW) (hpw : 0 ≤ pinW) :
    0 ≤ weightedDensity area pins maxArea maxPins areaW pinW :=
  add_nonneg (mul_nonneg haw (div_nonneg ha hma.le))
             (mul_nonneg hpw (div_nonneg hp hmp.le))

def normalizeTo01 (val maxVal : Real) : Real := if 0 < maxVal then val / maxVal else val

theorem normalizeTo01_mem {val maxVal : Real}
    (h0 : 0 ≤ val) (hle : val ≤ maxVal) (hpos : 0 < maxVal) :
    0 ≤ normalizeTo01 val maxVal ∧ normalizeTo01 val maxVal ≤ 1 := by
  unfold normalizeTo01
  rw [if_pos hpos]
  exact ⟨div_nonneg h0 hpos.le, (div_le_one hpos).mpr hle⟩

def getDensityDirty (val lastMaxUtil : Real) : Real := min (val / lastMaxUtil) 1

theorem getDensityDirty_le_one (val lastMaxUtil : Real) :
    getDensityDirty val lastMaxUtil ≤ 1 := min_le_right _ _

theorem getDensityDirty_nonneg {val lastMaxUtil : Real}
    (h : 0 ≤ val) (hp : 0 < lastMaxUtil) : 0 ≤ getDensityDirty val lastMaxUtil :=
  le_min (div_nonneg h hp.le) (by norm_num)

theorem getDensityDirty_mem {val lastMaxUtil : Real}
    (h : 0 ≤ val) (hp : 0 < lastMaxUtil) :
    0 ≤ getDensityDirty val lastMaxUtil ∧ getDensityDirty val lastMaxUtil ≤ 1 :=
  ⟨getDensityDirty_nonneg h hp, getDensityDirty_le_one val lastMaxUtil⟩

def listMax (l : List Real) : Real := l.foldl max 0

theorem foldl_max_ge_init (l : List Real) (a : Real) : a ≤ l.foldl max a := by
  induction l generalizing a with
  | nil => simp
  | cons x xs ih => exact le_trans (le_max_left a x) (ih (max a x))

theorem le_foldl_max {x : Real} : ∀ (l : List Real) (a : Real), x ∈ l → x ≤ l.foldl max a := by
  intro l
  induction l with
  | nil => intro a hx; simp at hx
  | cons y ys ih =>
    intro a hx
    rcases List.mem_cons.mp hx with h | h
    · subst h; exact le_trans (le_max_right a x) (foldl_max_ge_init ys (max a x))
    · exact ih (max a y) h

theorem listMax_nonneg (l : List Real) : 0 ≤ listMax l := foldl_max_ge_init l 0

theorem le_listMax {x : Real} {l : List Real} (hx : x ∈ l) : x ≤ listMax l :=
  le_foldl_max l 0 hx

def adaptiveWeight (avgHpwlDelta avgCongImprove userKnob siteWidth : Real) : Real :=
  if 0 < avgCongImprove then (avgHpwlDelta / avgCongImprove) * userKnob
  else 0.5 * siteWidth

def adaptiveWeightFallback (siteWidth : Real) : Real := 1.0 * siteWidth

theorem adaptiveWeight_nonneg {avgHpwlDelta avgCongImprove userKnob siteWidth : Real}
    (h1 : 0 ≤ avgHpwlDelta) (h2 : 0 ≤ userKnob) (h3 : 0 ≤ siteWidth) :
    0 ≤ adaptiveWeight avgHpwlDelta avgCongImprove userKnob siteWidth := by
  unfold adaptiveWeight
  by_cases hc : 0 < avgCongImprove
  · rw [if_pos hc]; exact mul_nonneg (div_nonneg h1 hc.le) h2
  · rw [if_neg hc]; positivity

theorem adaptiveWeightFallback_nonneg {siteWidth : Real} (h : 0 ≤ siteWidth) :
    0 ≤ adaptiveWeightFallback siteWidth := by unfold adaptiveWeightFallback; linarith

structure MoveRecord where
  origDensity : Real
  newDensity : Real
  contrib : Real

def congImprovement (moves : List MoveRecord) : Real :=
  moves.foldl (fun a m => a + (m.origDensity - m.newDensity) * m.contrib) 0

theorem foldl_congImprove_nonneg :
    ∀ (moves : List MoveRecord) (acc : Real), 0 ≤ acc →
      (∀ m ∈ moves, m.newDensity ≤ m.origDensity ∧ 0 ≤ m.contrib) →
      0 ≤ List.foldl (fun a m => a + (m.origDensity - m.newDensity) * m.contrib) acc moves := by
  intro moves
  induction moves with
  | nil => intro acc h _; simpa using h
  | cons m ms ih =>
    intro acc hacc hall
    simp only [List.foldl_cons]
    apply ih
    · have hm := hall m List.mem_cons_self
      have hterm : 0 ≤ (m.origDensity - m.newDensity) * m.contrib :=
        mul_nonneg (by linarith [hm.1]) hm.2
      linarith
    · intro x hx; exact hall x (List.mem_cons_of_mem m hx)

theorem congImprovement_nonneg (moves : List MoveRecord)
    (h : ∀ m ∈ moves, m.newDensity ≤ m.origDensity ∧ 0 ≤ m.contrib) :
    0 ≤ congImprovement moves :=
  foldl_congImprove_nonneg moves 0 le_rfl h

def combinedProfit (hpwlDelta congWeight congImprove : Real) : Real :=
  hpwlDelta + congWeight * congImprove

def maxAllowedHpwl (isProfiling : Bool) (initHpwl budget : Real) : Real :=
  if isProfiling then initHpwl * 2 else budget

def accepted (newHpwl budget hpwlDelta congWeight congImprove : Real) : Prop :=
  newHpwl ≤ budget ∧ 0 < combinedProfit hpwlDelta congWeight congImprove

theorem accepted_respects_budget {newHpwl budget hd cw ci : Real}
    (h : accepted newHpwl budget hd cw ci) : newHpwl ≤ budget := h.1

theorem accepted_profitable {newHpwl budget hd cw ci : Real}
    (h : accepted newHpwl budget hd cw ci) : 0 < combinedProfit hd cw ci := h.2

theorem budget_violation_rejected {newHpwl budget hd cw ci : Real} (h : budget < newHpwl) :
    ¬ accepted newHpwl budget hd cw ci := by
  rintro ⟨hb, _⟩; exact absurd hb (not_le.mpr h)

theorem accepted_mono_profit {newHpwl budget hd1 hd2 cw ci : Real}
    (h : accepted newHpwl budget hd1 cw ci)
    (hle : combinedProfit hd1 cw ci ≤ combinedProfit hd2 cw ci) :
    accepted newHpwl budget hd2 cw ci :=
  ⟨h.1, lt_of_lt_of_le h.2 hle⟩

theorem pass1_accept_iff (newHpwl budget hd ci : Real) :
    accepted newHpwl budget hd 0 ci ↔ (newHpwl ≤ budget ∧ 0 < hd) := by
  simp [accepted, combinedProfit]

def effProfilingExcess (pe : Real) : Real := if pe ≤ 0 then 1.10 else pe

theorem effProfilingExcess_pos (pe : Real) : 0 < effProfilingExcess pe := by
  unfold effProfilingExcess
  by_cases h : pe ≤ 0
  · rw [if_pos h]; norm_num
  · rw [if_neg h]; exact not_le.mp h

def budgetFromProfiling (optimalHpwl pe : Real) : Real := optimalHpwl * effProfilingExcess pe

theorem budgetFromProfiling_admits_optimum_default {optimalHpwl pe : Real}
    (h : 0 ≤ optimalHpwl) (hpe : pe ≤ 0) :
    optimalHpwl ≤ budgetFromProfiling optimalHpwl pe := by
  unfold budgetFromProfiling effProfilingExcess
  rw [if_pos hpe]; nlinarith

theorem budgetFromProfiling_admits_optimum {optimalHpwl pe : Real}
    (h : 0 ≤ optimalHpwl) (hpe : 1 ≤ pe) :
    optimalHpwl ≤ budgetFromProfiling optimalHpwl pe := by
  unfold budgetFromProfiling effProfilingExcess
  rw [if_neg (by linarith)]
  exact le_mul_of_one_le_right h hpe

theorem default_budget_admits_optimum {optimalHpwl : Real} (h : 0 ≤ optimalHpwl) :
    optimalHpwl ≤ budgetFromProfiling optimalHpwl 1.10 :=
  budgetFromProfiling_admits_optimum h (by norm_num)

def budgetForIteration (optimalHpwl mult : Real) : Real := optimalHpwl * mult

theorem budgetForIteration_admits_optimum {optimalHpwl mult : Real}
    (h : 0 ≤ optimalHpwl) (hm : 1 ≤ mult) :
    optimalHpwl ≤ budgetForIteration optimalHpwl mult :=
  le_mul_of_one_le_right h hm

theorem default_multipliers_ge_one :
    ∀ m ∈ ([1.50, 1.25, 1.10, 1.04] : List Real), 1 ≤ m := by
  intro m hm; fin_cases hm <;> norm_num

theorem default_iteration_admits_optimum {optimalHpwl : Real} (h : 0 ≤ optimalHpwl)
    {m : Real} (hm : m ∈ ([1.50, 1.25, 1.10, 1.04] : List Real)) :
    optimalHpwl ≤ budgetForIteration optimalHpwl m :=
  budgetForIteration_admits_optimum h (default_multipliers_ge_one m hm)

theorem profiling_maxAllowed_admits_noMove {initHpwl budget : Real} (h : 0 ≤ initHpwl) :
    initHpwl ≤ maxAllowedHpwl true initHpwl budget := by
  unfold maxAllowedHpwl; rw [if_pos rfl]; linarith

structure CandidateMove where
  hpwlDelta : Real
  congImprove : Real

def stepHpwl (maxAllowed congWeight currHpwl hpwlDelta congImprove : Real) : Real :=
  if currHpwl - hpwlDelta ≤ maxAllowed then
    if 0 < combinedProfit hpwlDelta congWeight congImprove then currHpwl - hpwlDelta
    else currHpwl
  else currHpwl

theorem stepHpwl_le_budget (maxAllowed congWeight currHpwl hpwlDelta congImprove : Real)
    (h : currHpwl ≤ maxAllowed) :
    stepHpwl maxAllowed congWeight currHpwl hpwlDelta congImprove ≤ maxAllowed := by
  unfold stepHpwl
  by_cases h1 : currHpwl - hpwlDelta ≤ maxAllowed
  · rw [if_pos h1]
    by_cases h2 : 0 < combinedProfit hpwlDelta congWeight congImprove
    · rw [if_pos h2]; exact h1
    · rw [if_neg h2]; exact h
  · rw [if_neg h1]; exact h

theorem stepHpwl_profiling_le (maxAllowed currHpwl hpwlDelta congImprove : Real) :
    stepHpwl maxAllowed 0 currHpwl hpwlDelta congImprove ≤ currHpwl := by
  unfold stepHpwl
  by_cases h1 : currHpwl - hpwlDelta ≤ maxAllowed
  · rw [if_pos h1]
    by_cases h2 : 0 < combinedProfit hpwlDelta 0 congImprove
    · rw [if_pos h2]
      have hd : combinedProfit hpwlDelta 0 congImprove = hpwlDelta := by simp [combinedProfit]
      rw [hd] at h2; linarith
    · rw [if_neg h2]
  · rw [if_neg h1]

def runCandidates (maxAllowed congWeight : Real) (init : Real)
    (moves : List CandidateMove) : Real :=
  moves.foldl (fun cur m => stepHpwl maxAllowed congWeight cur m.hpwlDelta m.congImprove) init

theorem foldl_step_le_budget (maxAllowed congWeight : Real) :
    ∀ (moves : List CandidateMove) (init : Real), init ≤ maxAllowed →
      List.foldl (fun cur m => stepHpwl maxAllowed congWeight cur m.hpwlDelta m.congImprove)
        init moves ≤ maxAllowed := by
  intro moves
  induction moves with
  | nil => intro init h; simpa using h
  | cons m ms ih =>
    intro init h
    simp only [List.foldl_cons]
    exact ih _ (stepHpwl_le_budget _ _ _ _ _ h)

theorem runCandidates_le_budget (maxAllowed congWeight : Real) (moves : List CandidateMove)
    (init : Real) (h : init ≤ maxAllowed) :
    runCandidates maxAllowed congWeight init moves ≤ maxAllowed := by
  unfold runCandidates; exact foldl_step_le_budget maxAllowed congWeight moves init h

theorem foldl_profiling_le (maxAllowed : Real) :
    ∀ (moves : List CandidateMove) (init : Real),
      List.foldl (fun cur m => stepHpwl maxAllowed 0 cur m.hpwlDelta m.congImprove)
        init moves ≤ init := by
  intro moves
  induction moves with
  | nil => intro init; simp
  | cons m ms ih =>
    intro init
    simp only [List.foldl_cons]
    exact le_trans (ih _) (stepHpwl_profiling_le _ _ _ _)

theorem runCandidates_profiling_le (maxAllowed : Real) (moves : List CandidateMove)
    (init : Real) :
    runCandidates maxAllowed 0 init moves ≤ init := by
  unfold runCandidates; exact foldl_profiling_le maxAllowed moves init

def converged (last curr tol : Real) : Prop := last = 0 ∨ |curr - last| / last ≤ tol

def runPasses (fuel : Nat) (curr tol : Real) (step : Real → Real) : Real :=
  match fuel with
  | 0 => curr
  | n + 1 =>
    let next := step curr
    if curr = 0 ∨ |next - curr| / curr ≤ tol then next else runPasses n next tol step

theorem runPasses_zero (curr tol : Real) (step : Real → Real) :
    runPasses 0 curr tol step = curr := rfl

theorem runPasses_le (tol : Real) (step : Real → Real) (hstep : ∀ x, step x ≤ x) :
    ∀ (fuel : Nat) (curr : Real), runPasses fuel curr tol step ≤ curr := by
  intro fuel
  induction fuel with
  | zero => intro curr; simp [runPasses]
  | succ n ih =>
    intro curr
    unfold runPasses
    by_cases hc : curr = 0 ∨ |step curr - curr| / curr ≤ tol
    · simp only [hc, if_true]; exact hstep curr
    · simp only [hc, if_false]
      exact le_trans (ih (step curr)) (hstep curr)

def dispSchedule (iter : Nat) (chipW chipH origX origY : Int) : Int × Int :=
  if iter = 0 then (chipW, chipH)
  else if iter = 1 then (10 * origX, 10 * origY)
  else (origX, origY)

theorem dispSchedule_iter0 (chipW chipH origX origY : Int) :
    dispSchedule 0 chipW chipH origX origY = (chipW, chipH) := rfl

theorem dispSchedule_iter1 (chipW chipH origX origY : Int) :
    dispSchedule 1 chipW chipH origX origY = (10 * origX, 10 * origY) := rfl

theorem dispSchedule_restored {iter : Nat} (h : 2 ≤ iter)
    (chipW chipH origX origY : Int) :
    dispSchedule iter chipW chipH origX origY = (origX, origY) := by
  unfold dispSchedule
  have h0 : iter ≠ 0 := by omega
  have h1 : iter ≠ 1 := by omega
  rw [if_neg h0, if_neg h1]

def finalDisplacement (origX origY : Int) : Int × Int := (origX, origY)

theorem finalDisplacement_restores (origX origY : Int) :
    finalDisplacement origX origY = (origX, origY) := rfl

theorem stepHpwl_le_of_le {maxAllowed congWeight currHpwl hpwlDelta congImprove M : Real}
    (hc : currHpwl ≤ M) (hM : maxAllowed ≤ M) :
    stepHpwl maxAllowed congWeight currHpwl hpwlDelta congImprove ≤ M := by
  unfold stepHpwl
  by_cases h1 : currHpwl - hpwlDelta ≤ maxAllowed
  · rw [if_pos h1]
    by_cases h2 : 0 < combinedProfit hpwlDelta congWeight congImprove
    · rw [if_pos h2]; exact le_trans h1 hM
    · rw [if_neg h2]; exact hc
  · rw [if_neg h1]; exact hc

theorem foldl_step_le_of_le (maxAllowed congWeight M : Real) (hM : maxAllowed ≤ M) :
    ∀ (moves : List CandidateMove) (init : Real), init ≤ M →
      List.foldl (fun cur m => stepHpwl maxAllowed congWeight cur m.hpwlDelta m.congImprove)
        init moves ≤ M := by
  intro moves
  induction moves with
  | nil => intro init h; simpa using h
  | cons m ms ih =>
    intro init h
    simp only [List.foldl_cons]
    exact ih _ (stepHpwl_le_of_le h hM)

theorem runCandidates_le_init (maxAllowed congWeight : Real) (init : Real)
    (moves : List CandidateMove) :
    runCandidates maxAllowed congWeight init moves ≤ max init maxAllowed := by
  unfold runCandidates
  exact foldl_step_le_of_le maxAllowed congWeight (max init maxAllowed)
    (le_max_right _ _) moves init (le_max_left _ _)

def pass2Iteration (optimalHpwl mult congWeight currHpwl : Real)
    (moves : List CandidateMove) : Real :=
  runCandidates (budgetForIteration optimalHpwl mult) congWeight currHpwl moves

theorem pass2Iteration_le_budget {optimalHpwl mult congWeight currHpwl : Real}
    (moves : List CandidateMove) (h : currHpwl ≤ budgetForIteration optimalHpwl mult) :
    pass2Iteration optimalHpwl mult congWeight currHpwl moves
      ≤ budgetForIteration optimalHpwl mult := by
  unfold pass2Iteration
  exact runCandidates_le_budget _ _ _ _ h

def runPass2 (optimalHpwl congWeight : Real) (init : Real)
    (schedule : List (Real × List CandidateMove)) : Real :=
  schedule.foldl (fun cur s => pass2Iteration optimalHpwl s.1 congWeight cur s.2) init

theorem runPass2_nil (optimalHpwl congWeight init : Real) :
    runPass2 optimalHpwl congWeight init [] = init := rfl

theorem runPass2_le_common_budget (optimalHpwl congWeight B : Real) :
    ∀ (schedule : List (Real × List CandidateMove)) (init : Real),
      init ≤ B → (∀ s ∈ schedule, budgetForIteration optimalHpwl s.1 ≤ B) →
      runPass2 optimalHpwl congWeight init schedule ≤ B := by
  intro schedule
  induction schedule with
  | nil => intro init h _; simpa [runPass2] using h
  | cons s ss ih =>
    intro init h hall
    simp only [runPass2, List.foldl_cons]
    have hstage : budgetForIteration optimalHpwl s.1 ≤ B := hall s List.mem_cons_self

    have hstep : pass2Iteration optimalHpwl s.1 congWeight init s.2 ≤ B := by
      unfold pass2Iteration
      by_cases hb : init ≤ budgetForIteration optimalHpwl s.1
      · exact le_trans (runCandidates_le_budget _ _ _ _ hb) hstage
      ·

        have : runCandidates (budgetForIteration optimalHpwl s.1) congWeight init s.2
            ≤ max init B :=
          le_trans (runCandidates_le_init _ _ _ _)
            (max_le_max (le_refl init) hstage)
        exact le_trans this (le_of_eq (max_eq_right h))
    exact ih _ hstep (fun x hx => hall x (List.mem_cons_of_mem s hx))

theorem default_tradeoff_mem :
    0 ≤ tradeoffRun defaultParams.tradeoff ∧ tradeoffRun defaultParams.tradeoff ≤ 1 :=
  tradeoffRun_mem _

theorem default_passes_pos : 0 < defaultParams.passes := by norm_num [defaultParams]

theorem default_profiling_excess_ge_one : (1 : Real) ≤ defaultParams.profiling_excess := by
  norm_num [defaultParams]

theorem default_run_budget_admits_optimum {optimalHpwl : Real} (h : 0 ≤ optimalHpwl) :
    optimalHpwl ≤ budgetFromProfiling optimalHpwl defaultParams.profiling_excess :=
  budgetFromProfiling_admits_optimum h default_profiling_excess_ge_one

end

end OpenROAD.WL
