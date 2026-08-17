import Mathlib

namespace OpenROAD.PWR

noncomputable section

structure Params where

  setupSlackMargin : Real := 1e-11

  setupSlackMaxMargin : Real := 1e-4

  slewCheckDepth : Nat := 2

  maxPasses : Nat := 10

  maxSwapsPerInstance : Nat := 16

  maxWnsDegradeFrac : Real := 0.02

  minPrintInterval : Nat := 10

  maxPrintInterval : Nat := 5000

def defaultParams : Params := {}

def clampR (x lo hi : Real) : Real := max lo (min hi x)

def clampN (x lo hi : Nat) : Nat := max lo (min hi x)

theorem clampR_ge_lo (x lo hi : Real) : lo ≤ clampR x lo hi := le_max_left _ _

theorem clampR_le_hi (x lo hi : Real) (h : lo ≤ hi) : clampR x lo hi ≤ hi :=
  max_le h (min_le_left _ _)

theorem clampR_mem (x lo hi : Real) (h : lo ≤ hi) :
    lo ≤ clampR x lo hi ∧ clampR x lo hi ≤ hi :=
  ⟨clampR_ge_lo x lo hi, clampR_le_hi x lo hi h⟩

theorem clampN_ge_lo (x lo hi : Nat) : lo ≤ clampN x lo hi := le_max_left _ _

theorem clampN_le_hi (x lo hi : Nat) (h : lo ≤ hi) : clampN x lo hi ≤ hi :=
  max_le h (min_le_left _ _)

theorem clampR_eq_self (x lo hi : Real) (h1 : lo ≤ x) (h2 : x ≤ hi) :
    clampR x lo hi = x := by
  unfold clampR
  rw [min_eq_right h2, max_eq_right h1]

def recoverPowerPercent (raw : Real) : Real := clampR raw 0 1

theorem recoverPowerPercent_mem (raw : Real) :
    0 ≤ recoverPowerPercent raw ∧ recoverPowerPercent raw ≤ 1 :=
  clampR_mem raw 0 1 (by norm_num)

theorem recoverPowerPercent_nonneg (raw : Real) : 0 ≤ recoverPowerPercent raw :=
  (recoverPowerPercent_mem raw).1

def minClockPeriod (periods : List Real) : Real :=
  match periods with
  | [] => 0
  | p :: ps => max 0 (ps.foldl (fun acc q => min acc q) p)

theorem foldl_min_le_head (p : Real) (ps : List Real) :
    ps.foldl (fun acc q => min acc q) p ≤ p := by
  induction ps generalizing p with
  | nil => simp
  | cons q t ih => simp only [List.foldl_cons]; exact le_trans (ih (min p q)) (min_le_left _ _)

theorem minClockPeriod_nonneg (periods : List Real) : 0 ≤ minClockPeriod periods := by
  unfold minClockPeriod
  cases periods with
  | nil => simp
  | cons p ps => exact le_max_left _ _

def computeWnsFloor (P : Params) (worstSetupBefore minPeriod rawPercent : Real) : Real :=
  if 0 ≤ worstSetupBefore then 0
  else if minPeriod ≤ 0 then worstSetupBefore
  else worstSetupBefore - P.maxWnsDegradeFrac * recoverPowerPercent rawPercent * minPeriod

theorem wns_budget_nonneg (P : Params) (minPeriod rawPercent : Real)
    (hf : 0 ≤ P.maxWnsDegradeFrac) (hp : 0 ≤ minPeriod) :
    0 ≤ P.maxWnsDegradeFrac * recoverPowerPercent rawPercent * minPeriod := by
  have := recoverPowerPercent_nonneg rawPercent
  positivity

theorem computeWnsFloor_le_worst (P : Params) (worstSetupBefore minPeriod rawPercent : Real)
    (hf : 0 ≤ P.maxWnsDegradeFrac) :
    computeWnsFloor P worstSetupBefore minPeriod rawPercent ≤ worstSetupBefore := by
  unfold computeWnsFloor
  by_cases h1 : 0 ≤ worstSetupBefore
  · simp [h1]
  · simp only [h1, if_false]
    by_cases h2 : minPeriod ≤ 0
    · simp [h2]
    · simp only [h2, if_false]
      push_neg at h2
      have hb := wns_budget_nonneg P minPeriod rawPercent hf (le_of_lt h2)
      linarith

theorem computeWnsFloor_closed (P : Params) (worstSetupBefore minPeriod rawPercent : Real)
    (h : 0 ≤ worstSetupBefore) :
    computeWnsFloor P worstSetupBefore minPeriod rawPercent = 0 := by
  unfold computeWnsFloor; simp [h]

def holdFloor (worstHoldBefore : Real) : Real :=
  if 0 ≤ worstHoldBefore then 0 else worstHoldBefore

theorem holdFloor_le_worst (w : Real) : holdFloor w ≤ w := by
  unfold holdFloor
  by_cases h : 0 ≤ w
  · simp [h]
  · simp [h]
theorem holdFloor_nonpos (w : Real) : holdFloor w ≤ 0 := by
  unfold holdFloor
  by_cases h : 0 ≤ w
  · simp [h]
  · simp only [h, if_false]; exact le_of_lt (lt_of_not_ge h)

structure Cand where
  inst : Nat
  slack : Real
  headroom : Real
  power : Real
  area : Int
  drivesClock : Bool

def candScore (c : Cand) : Real := c.power * max 0 c.headroom

theorem candScore_nonneg (c : Cand) (h : 0 ≤ c.power) : 0 ≤ candScore c := by
  unfold candScore
  have : (0 : Real) ≤ max 0 c.headroom := le_max_left _ _
  positivity

def candBefore (a b : Cand) : Bool :=
  if candScore a ≠ candScore b then decide (candScore b < candScore a)
  else if a.power ≠ b.power then decide (b.power < a.power)
  else if a.headroom ≠ b.headroom then decide (b.headroom < a.headroom)
  else decide (b.area < a.area)

theorem candBefore_score_ge (a b : Cand) (h : candBefore a b = true) :
    candScore b ≤ candScore a := by
  unfold candBefore at h
  by_cases hne : candScore a ≠ candScore b
  · rw [if_pos hne] at h
    exact le_of_lt (of_decide_eq_true h)
  · push_neg at hne
    exact le_of_eq hne.symm

def isEligible (P : Params) (c : Cand) (allowBufferRemoval : Bool) : Prop :=
  if c.drivesClock = true ∨ allowBufferRemoval = true then
    c.slack < P.setupSlackMaxMargin
  else
    c.headroom > P.setupSlackMargin ∧ c.slack < P.setupSlackMaxMargin

theorem eligible_headroom_pos (P : Params) (c : Cand)
    (hmargin : 0 ≤ P.setupSlackMargin)
    (hc : c.drivesClock = false)
    (h : isEligible P c false) :
    0 < c.headroom := by
  unfold isEligible at h
  simp only [hc, Bool.false_eq_true, or_self, if_false] at h
  exact lt_of_le_of_lt hmargin h.1

def headroomOf (slack wnsFloor : Real) : Real := slack - wnsFloor

theorem headroomOf_def (slack wnsFloor : Real) :
    headroomOf slack wnsFloor + wnsFloor = slack := by unfold headroomOf; ring

def instanceWorstSlack (dflt : Real) (slacks : List Real) : Real :=
  match slacks with
  | [] => dflt
  | s :: ss => ss.foldl (fun acc q => min acc q) s

theorem instanceWorstSlack_le_mem (dflt : Real) (slacks : List Real)
    (x : Real) (hx : x ∈ slacks) :
    instanceWorstSlack dflt slacks ≤ x := by
  cases slacks with
  | nil => simp at hx
  | cons s ss =>
    unfold instanceWorstSlack

    have key : ∀ (t : List Real) (a : Real),
        (∀ y ∈ t, t.foldl (fun acc q => min acc q) a ≤ y)
        ∧ t.foldl (fun acc q => min acc q) a ≤ a := by
      intro t
      induction t with
      | nil => intro a; exact ⟨by simp, le_refl _⟩
      | cons q r ih =>
        intro a
        refine ⟨?_, ?_⟩
        · intro y hy
          simp only [List.foldl_cons]
          rcases List.mem_cons.mp hy with h | h
          · subst h; exact le_trans (ih (min a y)).2 (min_le_right _ _)
          · exact (ih (min a q)).1 y h
        · simp only [List.foldl_cons]
          exact le_trans (ih (min a q)).2 (min_le_left _ _)
    rcases List.mem_cons.mp hx with h | h
    · rw [h]; exact (key ss s).2
    · exact (key ss s).1 x h

def maxInstCount (size rawCeil : Nat) : Nat := clampN rawCeil 1 size

theorem maxInstCount_mem (size rawCeil : Nat) (h : 1 ≤ size) :
    1 ≤ maxInstCount size rawCeil ∧ maxInstCount size rawCeil ≤ size :=
  ⟨clampN_ge_lo _ _ _, clampN_le_hi _ _ _ h⟩

def printInterval (P : Params) (maxInst : Nat) : Nat :=
  clampN (maxInst / 100) P.minPrintInterval P.maxPrintInterval

theorem printInterval_pos (P : Params) (maxInst : Nat) (h : 1 ≤ P.minPrintInterval) :
    1 ≤ printInterval P maxInst :=
  le_trans h (clampN_ge_lo _ _ _)

theorem printInterval_mem (P : Params) (maxInst : Nat)
    (h : P.minPrintInterval ≤ P.maxPrintInterval) :
    P.minPrintInterval ≤ printInterval P maxInst ∧
      printInterval P maxInst ≤ P.maxPrintInterval :=
  ⟨clampN_ge_lo _ _ _, clampN_le_hi _ _ _ h⟩

def maxConsecutiveRejects (maxInst : Nat) : Nat := clampN (maxInst / 10) 1000 20000

theorem maxConsecutiveRejects_mem (maxInst : Nat) :
    1000 ≤ maxConsecutiveRejects maxInst ∧ maxConsecutiveRejects maxInst ≤ 20000 :=
  ⟨clampN_ge_lo _ _ _, clampN_le_hi _ _ _ (by norm_num)⟩

theorem maxConsecutiveRejects_pos (maxInst : Nat) : 1 ≤ maxConsecutiveRejects maxInst :=
  le_trans (by norm_num) (maxConsecutiveRejects_mem maxInst).1

structure Cell where
  area : Int
  width : Int
  height : Int

def meetsSize (curr cand : Cell) : Bool :=
  decide (cand.width ≤ curr.width) && decide (cand.height = curr.height)

def smallerEligible (curr cand : Cell) : Bool :=
  decide (cand.height = curr.height) && decide (cand.width ≤ curr.width)
    && decide (cand.area < curr.area)

theorem smallerEligible_meetsSize (curr cand : Cell)
    (h : smallerEligible curr cand = true) : meetsSize curr cand = true := by
  unfold smallerEligible at h
  unfold meetsSize
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h ⊢
  exact ⟨h.1.2, h.1.1⟩

def targetArea (curr : Cell) (cands : List Cell) : Int :=
  cands.foldl (fun acc c => if smallerEligible curr c then max acc c.area else acc) (-1)

theorem targetArea_lt_curr (curr : Cell) (cands : List Cell) (h : 0 ≤ targetArea curr cands) :
    targetArea curr cands < curr.area := by
  unfold targetArea at h ⊢

  have key : ∀ (l : List Cell) (a : Int), (a ≤ -1 ∨ a < curr.area) →
      let r := l.foldl (fun acc c => if smallerEligible curr c then max acc c.area else acc) a
      r ≤ -1 ∨ r < curr.area := by
    intro l
    induction l with
    | nil => intro a ha; simpa using ha
    | cons c t ih =>
      intro a ha
      simp only [List.foldl_cons]
      by_cases hc : smallerEligible curr c
      · apply ih
        simp only [hc, if_true]

        have hca : c.area < curr.area := by
          unfold smallerEligible at hc
          simp only [Bool.and_eq_true, decide_eq_true_eq] at hc
          exact hc.2
        rcases ha with ha | ha
        ·
          rcases le_total a c.area with hle | hle
          · rw [max_eq_right hle]; exact Or.inr hca
          · rw [max_eq_left hle]; exact Or.inl ha
        ·
          exact Or.inr (max_lt ha hca)
      · simp only [hc, Bool.false_eq_true, if_false]
        exact ih a ha
  have := key cands (-1) (Or.inl (le_refl _))
  simp only at this
  rcases this with hbad | hgood
  · exact absurd h (by omega)
  · exact hgood

structure Drv where
  slew : Int
  cap : Int
  fanout : Int

def drvUpdate (curr pre post : Drv) : Drv :=
  ⟨curr.slew + (post.slew - pre.slew),
   curr.cap + (post.cap - pre.cap),
   curr.fanout + (post.fanout - pre.fanout)⟩

def drvOk (newC maxC : Drv) : Prop :=
  (0 ≤ newC.slew ∧ 0 ≤ newC.cap ∧ 0 ≤ newC.fanout) ∧
  (newC.slew ≤ maxC.slew ∧ newC.cap ≤ maxC.cap ∧ newC.fanout ≤ maxC.fanout)

def timingOk (wnsAfter holdAfter wnsFloor holdFloor : Real) : Prop :=
  wnsFloor ≤ wnsAfter ∧ holdFloor ≤ holdAfter

def moveAccept (wnsAfter holdAfter wnsFloor holdFloor : Real) (newC maxC : Drv) : Prop :=
  timingOk wnsAfter holdAfter wnsFloor holdFloor ∧ drvOk newC maxC

theorem accept_setup_floor {wa ha wf hf : Real} {n m : Drv}
    (h : moveAccept wa ha wf hf n m) : wf ≤ wa := h.1.1

theorem accept_hold_floor {wa ha wf hf : Real} {n m : Drv}
    (h : moveAccept wa ha wf hf n m) : hf ≤ ha := h.1.2

theorem accept_drv_within_max {wa ha wf hf : Real} {n m : Drv}
    (h : moveAccept wa ha wf hf n m) :
    n.slew ≤ m.slew ∧ n.cap ≤ m.cap ∧ n.fanout ≤ m.fanout := h.2.2

theorem accept_drv_nonneg {wa ha wf hf : Real} {n m : Drv}
    (h : moveAccept wa ha wf hf n m) :
    0 ≤ n.slew ∧ 0 ≤ n.cap ∧ 0 ≤ n.fanout := h.2.1

theorem accept_closed_keeps_wns {wa ha hf : Real} {n m : Drv}
    (h : moveAccept wa ha 0 hf n m) : 0 ≤ wa := h.1.1

structure LoopState where
  iteration : Nat := 0
  resizeCount : Nat := 0
  acceptedInPass : Nat := 0
  consecutiveRejects : Nat := 0
  stopped : Bool := false

def stepLoop (m : Nat) (accepted : Bool) (st : LoopState) : LoopState :=
  if st.stopped then st
  else
    { iteration := st.iteration + 1,
      resizeCount := if accepted then st.resizeCount + 1 else st.resizeCount,
      acceptedInPass := if accepted then st.acceptedInPass + 1 else st.acceptedInPass,
      consecutiveRejects := if accepted then 0 else st.consecutiveRejects + 1,
      stopped := m ≤ (if accepted then 0 else st.consecutiveRejects + 1) }

def runLoop (m : Nat) (decisions : List Bool) (st : LoopState) : LoopState :=
  decisions.foldl (fun s a => stepLoop m a s) st

theorem stepLoop_resize_le (m : Nat) (a : Bool) (st : LoopState) :
    st.resizeCount ≤ (stepLoop m a st).resizeCount := by
  unfold stepLoop
  by_cases h : st.stopped
  · simp [h]
  · simp only [h]
    cases a <;> simp

theorem stepLoop_stopped_fix (m : Nat) (a : Bool) (st : LoopState) (h : st.stopped) :
    stepLoop m a st = st := by unfold stepLoop; simp [h]

theorem runLoop_resize_ge (m : Nat) (ds : List Bool) (st : LoopState) :
    st.resizeCount ≤ (runLoop m ds st).resizeCount := by
  unfold runLoop
  induction ds generalizing st with
  | nil => simp
  | cons a t ih =>
    simp only [List.foldl_cons]
    exact le_trans (stepLoop_resize_le m a st) (ih _)

theorem runLoop_stopped_fix (m : Nat) (ds : List Bool) (st : LoopState) (h : st.stopped) :
    runLoop m ds st = st := by
  unfold runLoop
  induction ds generalizing st with
  | nil => simp
  | cons a t ih =>
    simp only [List.foldl_cons]
    rw [stepLoop_stopped_fix m a st h]
    exact ih st h

theorem stepLoop_cr_lt (m : Nat) (a : Bool) (st : LoopState)
    (h : ¬ (stepLoop m a st).stopped) :
    (stepLoop m a st).consecutiveRejects < m := by
  unfold stepLoop at h ⊢
  by_cases hs : st.stopped
  · rw [if_pos hs] at h; exact absurd hs h
  · rw [if_neg hs] at h ⊢
    simp only [decide_eq_true_eq] at h
    exact lt_of_not_ge h

theorem runLoop_cr_lt (m : Nat) (ds : List Bool) :
    ∀ st : LoopState, st.consecutiveRejects < m →
      ¬ (runLoop m ds st).stopped →
      (runLoop m ds st).consecutiveRejects < m := by
  unfold runLoop
  induction ds with
  | nil => intro st hst h; simpa using hst
  | cons a t ih =>
    intro st hst h
    simp only [List.foldl_cons] at h ⊢
    by_cases hs' : (stepLoop m a st).stopped
    · have hfix : List.foldl (fun s a => stepLoop m a s) (stepLoop m a st) t
            = stepLoop m a st := runLoop_stopped_fix m t _ hs'
      rw [hfix] at h; exact absurd hs' h
    · exact ih (stepLoop m a st) (stepLoop_cr_lt m a st hs') h

theorem stepLoop_acc_eq_resize (m : Nat) (a : Bool) (st : LoopState)
    (h : st.acceptedInPass = st.resizeCount) :
    (stepLoop m a st).acceptedInPass = (stepLoop m a st).resizeCount := by
  unfold stepLoop
  by_cases hs : st.stopped
  · simp [hs, h]
  · simp only [hs]
    cases a <;> simp [h]

theorem runLoop_acc_eq_resize (m : Nat) (ds : List Bool) (st : LoopState)
    (h : st.acceptedInPass = st.resizeCount) :
    (runLoop m ds st).acceptedInPass = (runLoop m ds st).resizeCount := by
  unfold runLoop
  induction ds generalizing st with
  | nil => simpa using h
  | cons a t ih =>
    simp only [List.foldl_cons]
    exact ih _ (stepLoop_acc_eq_resize m a st h)

theorem stepLoop_acc_le_succ (m : Nat) (a : Bool) (st : LoopState) :
    (stepLoop m a st).acceptedInPass ≤ st.acceptedInPass + (if a then 1 else 0) := by
  unfold stepLoop
  by_cases hs : st.stopped
  · simp [hs]
  · simp only [hs]
    cases a <;> simp

def runPasses (m : Nat) (passes : List (List Bool)) (st : LoopState) : LoopState :=
  match passes with
  | [] => st
  | ds :: rest =>
    let st' := runLoop m ds { st with acceptedInPass := 0 }
    if st'.acceptedInPass = 0 then st'
    else runPasses m rest st'

theorem runPasses_resize_ge (m : Nat) (passes : List (List Bool)) (st : LoopState) :
    st.resizeCount ≤ (runPasses m passes st).resizeCount := by
  induction passes generalizing st with
  | nil => simp [runPasses]
  | cons ds rest ih =>
    unfold runPasses
    have hstep : st.resizeCount ≤ (runLoop m ds { st with acceptedInPass := 0 }).resizeCount := by
      have := runLoop_resize_ge m ds { st with acceptedInPass := 0 }
      simpa using this
    by_cases hz : (runLoop m ds { st with acceptedInPass := 0 }).acceptedInPass = 0
    · simp only [hz, if_true]; exact hstep
    · simp only [hz, if_false]
      exact le_trans hstep (ih _)

theorem runPasses_terminates (m : Nat) (passes : List (List Bool)) (st : LoopState) :
    passes = [] ∨
    ∃ ds rest st', passes = ds :: rest ∧
      st' = runLoop m ds { st with acceptedInPass := 0 } ∧
      (st'.acceptedInPass = 0 → runPasses m passes st = st') := by
  cases passes with
  | nil => exact Or.inl rfl
  | cons ds rest =>
    refine Or.inr ⟨ds, rest, runLoop m ds { st with acceptedInPass := 0 }, rfl, rfl, ?_⟩
    intro hz; unfold runPasses; simp [hz]

def recoverPowerResult (rawPercent : Real) (resizeCount bufferRemoveCount : Nat) : Bool :=
  if rawPercent ≤ 0 then false
  else decide (0 < resizeCount ∨ 0 < bufferRemoveCount)

theorem recoverPower_nonpos_effort (rawPercent : Real) (rc brc : Nat)
    (h : rawPercent ≤ 0) : recoverPowerResult rawPercent rc brc = false := by
  unfold recoverPowerResult; simp [h]

theorem recoverPower_success_iff (rawPercent : Real) (rc brc : Nat)
    (h : ¬ rawPercent ≤ 0) :
    recoverPowerResult rawPercent rc brc = true ↔ (0 < rc ∨ 0 < brc) := by
  unfold recoverPowerResult; simp [h]

theorem wns_floor_zero_percent (P : Params) (worst minPeriod : Real)
    (hneg : ¬ 0 ≤ worst) (hpos : 0 < minPeriod) :
    computeWnsFloor P worst minPeriod 0 = worst := by
  unfold computeWnsFloor
  rw [if_neg hneg, if_neg (not_le.mpr hpos)]
  have : recoverPowerPercent 0 = 0 := clampR_eq_self 0 0 1 (le_refl 0) (by norm_num)
  rw [this]; ring

theorem maxInstCount_singleton (rawCeil : Nat) : maxInstCount 1 rawCeil = 1 := by
  unfold maxInstCount clampN
  omega

theorem runLoop_nil (m : Nat) (st : LoopState) : runLoop m [] st = st := by
  unfold runLoop; simp

theorem runPasses_stops_on_zero (m : Nat) (ds : List Bool) (rest : List (List Bool))
    (st : LoopState)
    (hz : (runLoop m ds { st with acceptedInPass := 0 }).acceptedInPass = 0) :
    runPasses m (ds :: rest) st = runLoop m ds { st with acceptedInPass := 0 } := by
  unfold runPasses; simp [hz]

end

end OpenROAD.PWR
