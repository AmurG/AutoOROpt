import Mathlib

namespace OpenROAD

-- A tiny Real-valued model of the OpenROAD timing-driven net weight computation:
-- the patch clamps the computed weight into [1, netWeightMax].

def netWeightMax (max_param : Real) : Real :=
  max 1 max_param

def clamp (x lo hi : Real) : Real :=
  max lo (min hi x)

noncomputable def timingWeight (net_weight_max slack_max slack_min net_slack : Real) : Real :=
  let hi := netWeightMax net_weight_max
  let raw :=
    1 + (hi - 1) * (slack_max - net_slack) / (slack_max - slack_min)
  clamp raw 1 hi

theorem netWeightMax_ge_one (max_param : Real) : 1 ≤ netWeightMax max_param := by
  exact le_max_left _ _

theorem clamp_bounds (x lo hi : Real) (h : lo ≤ hi) :
    lo ≤ clamp x lo hi ∧ clamp x lo hi ≤ hi := by
  exact ⟨ le_max_left _ _, by exact max_le h ( min_le_left _ _ ) ⟩

theorem timingWeight_bounds (net_weight_max slack_max slack_min net_slack : Real) :
    1 ≤ timingWeight net_weight_max slack_max slack_min net_slack ∧
      timingWeight net_weight_max slack_max slack_min net_slack ≤ netWeightMax net_weight_max := by
  exact ⟨ by exact le_max_left _ _, by exact max_le_iff.mpr ⟨ by linarith [ netWeightMax_ge_one net_weight_max ], min_le_left _ _ ⟩ ⟩

end OpenROAD