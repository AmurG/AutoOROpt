### **Proposal: Lightweight Timing-Driven Detailed Placement with Pre-computed Slack Budgets**

#### **1. High-Level Objective**

The goal is to enhance the OpenROAD detailed placer (`detailed_placement`) to become timing-aware, preventing it from degrading the circuit's timing performance (Total Negative Slack - TNS, and Worst Negative Slack - WNS) while it optimizes for wirelength (HPWL).

This will be achieved by implementing a lightweight version of the "First, do no harm" principle from the `Hippocrates` paper (`RenPANV07`). The core idea is to perform a single static timing analysis (STA) *before* the main optimization loop to calculate a "timing budget" for every signal path. The detailed placer will then use these static, pre-computed budgets to quickly evaluate the timing impact of each potential move *without* needing to call the timer again.

This approach closes a significant gap in the current OpenROAD flow where `detailed_placement` is purely geometric, and timing repair (`repair_design`) is a separate, netlist-altering step. This proposal integrates timing-awareness directly into the geometric optimization.

#### **2. Core Idea: The "Pin Timing Budget"**

1.  **Current State:** A standard detailed placer might swap two cells to reduce HPWL by 50μm. However, if one of those cells is on a near-critical timing path, the small change in wirelength could be enough to push that path into negative slack, degrading the overall TNS.

2.  **Proposed Mechanism:**
    *   Before optimization, we use OpenSTA to find the slack of every pin in the design.
    *   For each logic gate (a `Node`), we identify its most critical input pin (the one with the worst slack).
    *   For every *other* input pin on that same gate, we calculate its **Pin Timing Budget**. This budget is the difference between its slack and the slack of the most critical input pin.
    *   `Budget(pin_j) = Slack(pin_j) - Slack(critical_pin_for_gate)`
    *   This budget represents the maximum amount of additional delay that can be added to the path leading to `pin_j` before it *becomes* the new critical path for that gate. For the most critical pin, this budget is zero.

3.  **The "Do No Harm" Constraint:** During optimization, before accepting any move (e.g., a swap or reordering), we estimate the delay change (`Δdelay`) it would cause on affected nets. A move is considered "timing-safe" only if for every affected sink pin, `Δdelay` is less than or equal to its pre-computed `Pin Timing Budget`.

This simple, local check provides a conservative guarantee that the move will not worsen the timing of the overall design.

#### **3. Architectural Integration Plan**

This proposal leverages the existing `DetailedObjective` framework, which is designed for extensibility. We will introduce a new objective class that acts as a timing *constraint checker* rather than a cost function to be minimized.

*   **Files to be Modified:**
    *   `src/dpl/src/detailed_manager.h` & `.cpp` (To orchestrate the new logic)
    *   `src/dpl/src/Opendp.cpp` (To trigger the initial STA and timing budget calculation)
*   **New Files to be Created:**
    *   `src/dpl/src/detailed_timing.h` & `.cpp` (To implement the new timing constraint objective)

The core placement logic in `Place.cpp` and the move generators (`detailed_global.h`, `detailed_reorder.h`, etc.) will **not** need to be changed. They will continue to propose moves, which will then be filtered by the `DetailedMgr` using our new timing constraint.

#### **4. Detailed Implementation Steps**

**Step 1: Create the `DetailedTiming` Constraint Class**

Create new files `detailed_timing.h` and `detailed_timing.cpp`.

```cpp
// In detailed_timing.h
#pragma once

#include "detailed_objective.h"
#include "odb/db.h"
#include "sta/Sta.hh"

#include <unordered_map>

namespace dpl {

class DetailedTiming : public DetailedObjective
{
 public:
  DetailedTiming(odb::dbDatabase* db, sta::Sta* sta, utl::Logger* logger);

  // Calculate and store timing budgets for all relevant pins.
  void init();

  // This objective is a constraint, not a cost.
  // We won't use curr(), accept(), or reject().
  double curr() override { return 0.0; }
  void accept() override {}
  void reject() override {}

  // The core constraint check. Returns 0.0 if safe, FLT_MAX if unsafe.
  double delta(const Journal& journal) override;

 private:
  // Data structure to hold the pre-computed budgets.
  std::unordered_map<odb::dbITerm*, float> pin_budgets_;

  // A simple factor to convert HPWL change (in DBU) to delay (in seconds).
  // This should be made configurable later.
  float dbu_to_delay_factor_;

  odb::dbDatabase* db_;
  sta::Sta* sta_;
  utl::Logger* logger_;
};

}  // namespace dpl
```

**Step 2: Implement the `DetailedTiming` Logic**

In `detailed_timing.cpp`:

1.  **`DetailedTiming::init()`:**
    *   This is the most critical setup function. It will be called *once* before the main optimization loop.
    *   Ensure timing is up-to-date by calling `sta_->ensureLevelized()`, `sta_->findRequireds()`, etc.
    *   Iterate through all instances (`odb::dbInst`) in the design.
    *   For each instance, find its most critical input pin (`dbITerm`) by querying `sta_->instWorstSlack(inst, sta::MinMax::max())`. Let this be `critical_slack`.
    *   Iterate through all input `dbITerm`s of the instance again. For each pin `iterm`, get its slack: `pin_slack = sta_->termSlack(iterm, sta::MinMax::max())`.
    *   Calculate the budget: `float budget = pin_slack - critical_slack;`.
    *   Store the budget: `pin_budgets_[iterm] = budget;`.
    *   Initialize `dbu_to_delay_factor_`. Start with a reasonable, empirically derived constant (e.g., from characterization of a representative wire in the technology). This is a known simplification but effective for a first pass.

2.  **`DetailedTiming::delta(const Journal& journal)`:**
    *   This function checks if the moves recorded in the `journal` are timing-safe.
    *   Initialize a map `std::unordered_map<odb::dbNet*, double> net_hpwl_deltas;` to accumulate HPWL changes for each affected net.
    *   Iterate through the `JournalAction`s in the `journal`. For each moved cell, calculate the `ΔHPWL` for every net connected to it and accumulate the result in `net_hpwl_deltas`.
    *   Now, iterate through the `net_hpwl_deltas` map. For each `(net, hpwl_delta)` pair:
        *   If `hpwl_delta <= 0`, this net is getting shorter, which is assumed to be timing-safe. Continue.
        *   If `hpwl_delta > 0`:
            *   Estimate the delay increase: `float delay_increase = hpwl_delta * dbu_to_delay_factor_;`
            *   Iterate through the sink `dbITerm`s of the net.
            *   For each sink pin, retrieve its budget: `float budget = pin_budgets_[iterm];`.
            *   If `delay_increase > budget`, the move is unsafe. Immediately `return FLT_MAX;`.
    *   If all checks pass, `return 0.0;`.

**Step 3: Integrate `DetailedTiming` into `DetailedMgr`**

In `detailed_manager.h` and `.cpp`:

1.  **Add members:**
    ```cpp
    // In detailed_manager.h
    private:
      std::unique_ptr<DetailedTiming> timing_obj_{nullptr};
      bool timing_driven_{false};
    ```
2.  **Add a public method:** `void setTimingDriven(bool mode) { timing_driven_ = mode; }`
3.  **In `DetailedMgr::init()` or constructor:**
    *   After initializing other objectives, check if `timing_driven_` is true.
    *   If so, instantiate the timing objective: `timing_obj_ = std::make_unique<DetailedTiming>(db_, sta_, logger_);`
    *   Call the initialization: `timing_obj_->init();`.
4.  **Modify the optimization loop (e.g., `DetailedMgr::run` or equivalent):**
    *   This is the key change to the optimization logic.
    *   Inside the loop where a generator proposes moves and the `delta` of the primary objective (e.g., `hpwl_obj_`) is evaluated:
    ```cpp
    // Psuedo-code for the decision logic in DetailedMgr
    // after a generator returns a journal of proposed moves.

    double primary_delta = primary_obj_->delta(journal);

    // Only consider moves that improve the primary objective.
    if (primary_delta < 0) {
      bool timing_safe = true;
      if (timing_driven_ && timing_obj_) {
        if (timing_obj_->delta(journal) == FLT_MAX) {
          timing_safe = false;
        }
      }

      if (timing_safe) {
        // Accept the move
        primary_obj_->accept();
        // ... update placement, etc.
      } else {
        // Reject the move due to timing violation
        primary_obj_->reject();
      }
    } else {
      // Reject the move because it doesn't improve the primary objective
      primary_obj_->reject();
    }
    ```

**Step 4: Top-Level Orchestration in `Opendp.cpp`**

In the Tcl-exposed `detailed_placement` command implementation within `Opendp.cpp`:

1.  Add a new optional argument to the command, e.g., `-timing_driven`.
2.  If this flag is present:
    *   Ensure the prerequisites are met. Print a warning if parasitics haven't been estimated. Use `sta_->updateTiming(true)` to ensure the timer is fully up-to-date.
    *   Instantiate `DetailedMgr` and call `mgr->setTimingDriven(true);`.
3.  Proceed with the rest of the detailed placement flow as normal.

#### **5. Expected Outcome & Verification**

*   **QoR:** When run with the `-timing_driven` flag, the DPL should produce a final placement with significantly better TNS and WNS compared to the default flow. The HPWL improvement will likely be slightly less than the default flow, as some beneficial wirelength moves will be rejected because they are not timing-safe. This is the expected and desired trade-off.
*   **Runtime:** There will be a one-time, upfront runtime cost for the initial STA and budget calculation. The per-iteration overhead of the timing check inside `DetailedMgr` will be negligible, as it's a simple map lookup and comparison. Total runtime should increase only slightly.
*   **Verification:** To verify the implementation, run a design through both the default `detailed_placement` and the new `detailed_placement -timing_driven`. Report the final HPWL, TNS, and WNS for both runs. The timing-driven run should show a clear improvement in the timing metrics.

This proposal provides a concrete, actionable plan that is well-grounded in published research, fits cleanly into the existing OpenROAD DPL architecture, and delivers a high-value, incremental improvement to the tool's capabilities.