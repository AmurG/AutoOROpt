### **Implementation Plan Part 1: Architectural Foundation - LSMC Driver and Multi-Objective Engine**

#### **I. High-Level Objective**

This plan details the initial, foundational phase of enhancing the OpenROAD Detailed Placement (DPL) module. The goal is to replace the current, often scripted, sequence of greedy optimization passes with a more powerful and robust search framework. This will be achieved by implementing two core architectural components:

1.  **A Large-Step Markov Chain (LSMC) Metaheuristic Driver:** This will serve as the new top-level optimization loop. It is designed to effectively escape local minima, a common failure mode for purely greedy optimizers, especially in highly congested or complex designs.
2.  **A Pluggable Multi-Objective Cost Engine:** This will replace the current monolithic objective function with a flexible, weighted-sum model. It will allow the DPL engine to simultaneously optimize for multiple, often competing, design metrics (e.g., wirelength, displacement, and later, timing and manufacturability).

Upon completion of this phase, the DPL engine will have a more powerful search capability and a flexible architecture, ready to incorporate the advanced timing and DFM objectives described in subsequent parts of the overall plan. The user-facing `detailed_placement` command will remain unchanged, but its underlying engine will be fundamentally more capable.

---

#### **II. Component 1: Implementation of the LSMC Metaheuristic Driver**

The LSMC driver will be integrated into the main DPL orchestrator class, likely `dpl::DetailedMgr` (in `src/dpl/src/detailed_manager.h` and `.cpp`), which manages the optimization process.

##### **A. Modifying `dpl::DetailedParams` and `dpl::DetailedMgr`**

1.  **Add LSMC Configuration Parameters to `dpl::DetailedParams` (`src/dpl/src/detailed.h`):**
    The `DetailedParams` struct should be extended to include parameters for controlling the LSMC loop.

    ```cpp
    // In src/dpl/src/detailed.h, inside struct DetailedParams
    int lsmc_max_iterations = 20; // Maximum number of LSMC iterations.
    int lsmc_non_improving_limit = 5; // Terminate if no improvement after F iterations.
    float lsmc_kick_ratio = 0.1; // Percentage of movable cells to perturb in the "kick" phase.
    ```

2.  **Add State Management and LSMC Logic to `dpl::DetailedMgr` (`src/dpl/src/detailed_manager.h` and `.cpp`):**
    The `DetailedMgr` class will be augmented to manage the LSMC state and execute the main loop.

    *   **In `detailed_manager.h`:**
        *   Define a private struct to snapshot the placement state of a cell:
          ```cpp
          struct PlacementState {
              dpl::DbuPt position;
              odb::dbOrientType orientation;
          };
          ```
        *   Add new private member variables:
          ```cpp
          // LSMC parameters, copied from DetailedParams
          int lsmc_max_iterations_;
          int lsmc_non_improving_limit_;
          float lsmc_kick_ratio_;

          // LSMC state
          std::vector<PlacementState> best_placement_state_;
          dpl::Cost best_placement_cost_;
          ```
        *   Add new private helper methods:
          ```cpp
          void saveState(std::vector<PlacementState>& state);
          void restoreState(const std::vector<PlacementState>& state);
          void performKickMove();
          ```
        *   Add a new public method that will become the main entry point for optimization:
          ```cpp
          void runLSMCOptimization();
          ```

    *   **In `detailed_manager.cpp`:**
        *   **Constructor:** Initialize the new LSMC member variables from the `DetailedParams` object.
        *   **Implement `saveState` and `restoreState`:**
            *   `saveState`: Will iterate through all movable `Node` objects. For each `node`, it will store its current `left_`, `bottom_`, and `orient_` into the provided `std::vector<PlacementState>`. The vector should be pre-sized to the number of movable cells.
            *   `restoreState`: Will iterate through the saved `state` vector and the movable `Node`s simultaneously. For each `node`, it will update its position and orientation from the saved state. After updating the `Node`'s internal data, it must also update its footprint on the placement `Grid` (by calling `grid_->erasePixel(old_pos)` and `grid_->paintPixel(new_pos)` for the cell).

        *   **Implement `performKickMove`:**
            *   This function implements the randomized perturbation.
            *   Collect all movable `Node*` into a `std::vector<Node*> candidates`.
            *   Calculate the number of swaps to perform: `num_swaps = (candidates.size() * lsmc_kick_ratio_) / 2`.
            *   Shuffle the `candidates` vector using `Utility::random_shuffle`.
            *   Iterate `num_swaps` times. In each iteration, pick two consecutive cells from the shuffled vector, `cellA` and `cellB`.
            *   Check if a swap is legal. A simple check is to ensure they have the same width and height. A more robust check would verify that `cellA` can legally be placed at `cellB`'s location and vice-versa, considering site compatibility and row constraints.
            *   If the swap is legal, perform it by exchanging their positions and orientations and updating the placement `Grid`. Use the journaling system (`Journal`) to make these moves if it simplifies grid updates.

        *   **Implement `runLSMCOptimization`:** This will be the new main loop.
            ```cpp
            void DetailedMgr::runLSMCOptimization() {
                // Initialize best_placement_state_ and best_placement_cost_
                saveState(best_placement_state_);
                best_placement_cost_ = multi_objective_engine_->curr(); // Assumes MultiObjective is implemented

                int non_improving_iter = 0;
                for (int i = 0; i < lsmc_max_iterations_ && non_improving_iter < lsmc_non_improving_limit_; ++i) {
                    // === DESCENT PHASE ===
                    // Execute a sequence of greedy optimization generators.
                    // These generators will be modified to use the new MultiObjective engine.
                    runGenerator(std::make_unique<DetailedGlobalSwap>(...));
                    runGenerator(std::make_unique<DetailedReorderer>(...));
                    runGenerator(std::make_unique<DetailedMis>(...));
                    // etc.

                    Cost local_optimum_cost = multi_objective_engine_->curr();

                    // === SELECTION PHASE ===
                    if (local_optimum_cost < best_placement_cost_) {
                        saveState(best_placement_state_);
                        best_placement_cost_ = local_optimum_cost;
                        non_improving_iter = 0;
                        logger_->info(DPL, 1, "LSMC iter {}: Found new best solution. Cost={}", i, best_placement_cost_);
                    } else {
                        non_improving_iter++;
                        restoreState(best_placement_state_); // Revert to the best known state
                        logger_->info(DPL, 2, "LSMC iter {}: No improvement. Non-improving count={}", i, non_improving_iter);
                    }

                    // === KICK PHASE ===
                    if (non_improving_iter < lsmc_non_improving_limit_) {
                        performKickMove();
                    }
                }

                // Finalize by restoring the best solution found
                restoreState(best_placement_state_);
            }
            ```

##### **B. Top-Level Integration**

The existing top-level function that runs the DPL optimization (e.g., in `Opendp.cpp` or `detailed.cpp`) should be modified to call `detailed_mgr->runLSMCOptimization()` instead of its current sequence of generator calls.

---

#### **III. Component 2: The Pluggable Multi-Objective Engine**

This component provides the flexible cost function required by the LSMC driver and the optimization generators.

##### **A. Create New Files: `MultiObjective.h` and `MultiObjective.cpp`**

These files will be added to the `src/dpl/src/` directory.

*   **In `MultiObjective.h`:**
    ```cpp
    #pragma once

    #include <vector>
    #include <memory>
    #include "dpl/detailed_objective.h"

    namespace dpl {

    class MultiObjective : public DetailedObjective {
     public:
      MultiObjective(utl::Logger* logger);

      // Adds an objective with a specific weight. The MultiObjective object takes ownership.
      void addObjective(std::unique_ptr<DetailedObjective> objective, float weight);
      void clearObjectives();

      // Overridden methods from the DetailedObjective interface
      Cost curr() override;
      Cost delta(const Journal& journal) override;
      void accept(const Journal& journal) override;
      void reject(const Journal& journal) override;

     private:
      struct WeightedObjective {
        std::unique_ptr<DetailedObjective> objective;
        float weight;
      };
      std::vector<WeightedObjective> objectives_;
      utl::Logger* logger_;
    };

    } // namespace dpl
    ```

*   **In `MultiObjective.cpp`:**
    *   Implement the methods defined in the header.
    *   `addObjective`: Pushes a new `WeightedObjective` struct onto the `objectives_` vector.
    *   `curr()`: Iterates through `objectives_`, calls `obj->curr()`, multiplies by `weight`, and returns the sum.
    *   `delta()`: Iterates through `objectives_`, calls `obj->delta(journal)`, multiplies by `weight`, and returns the sum of weighted deltas.
    *   `accept()` and `reject()`: Iterate through `objectives_` and call the corresponding method on each component objective to allow them to update their internal state.

##### **B. Integration with `dpl::DetailedMgr`**

1.  **Modify `DetailedMgr` Class (`detailed_manager.h`):**
    *   The `DetailedMgr` will now own and manage the `MultiObjective` engine.
    *   Remove any existing `DetailedObjective*` member.
    *   Add a new private member:
        ```cpp
        std::unique_ptr<MultiObjective> multi_objective_engine_;
        ```
    *   Add a new private method for constructing the engine:
        ```cpp
        void buildObjectiveEngine();
        ```

2.  **Implement `buildObjectiveEngine` in `detailed_manager.cpp`:**
    *   This function is responsible for creating and configuring the `MultiObjective` instance based on `DetailedParams`.
    *   It will be called from the `DetailedMgr` constructor or an `init` method.

    ```cpp
    void DetailedMgr::buildObjectiveEngine() {
        multi_objective_engine_ = std::make_unique<MultiObjective>(logger_);

        // Read weights from DetailedParams and add objectives.
        // For now, we will add the existing objectives. Later parts will add new ones.
        if (params_.hpwl_weight > 0) {
            multi_objective_engine_->addObjective(
                std::make_unique<DetailedHPWL>(network_, grid_), params_.hpwl_weight);
        }
        if (params_.displacement_weight > 0) {
            multi_objective_engine_->addObjective(
                std::make_unique<DetailedDisplacement>(network_, grid_), params_.displacement_weight);
        }
        // Add other existing objectives like ABU if needed
        if (params_.abu_weight > 0) {
            multi_objective_engine_->addObjective(
                std::make_unique<DetailedABU>(network_, grid_), params_.abu_weight);
        }
    }
    ```
    *   This requires adding `hpwl_weight`, `displacement_weight`, etc., to `DetailedParams.h` if they do not already exist.

3.  **Refactor Optimization Generators:**
    *   All `DetailedGenerator` implementations (e.g., `DetailedGlobalSwap`, `DetailedReorderer`, `DetailedMis`) must be refactored.
    *   Currently, they likely access a specific objective (e.g., HPWL) directly or through the manager.
    *   They must be changed to use the generic `multi_objective_engine_` for all cost (`delta`) calculations.
    *   **Example Change in a Generator:**
        *   **Old Code (conceptual):** `Cost delta_hpwl = mgr->getHPWLEngine()->delta(journal);`
        *   **New Code:** `Cost total_delta = mgr->getMultiObjectiveEngine()->delta(journal);`
    *   The generators will now be guided by the combined, weighted cost, making them implicitly multi-objective aware.

---

#### **IV. Summary of Part 1 Deliverables**

Upon completion of this part, the DPL codebase will have:

1.  A new top-level optimization loop in `DetailedMgr.cpp` that implements the LSMC metaheuristic (`runLSMCOptimization`).
2.  Helper functions within `DetailedMgr.cpp` for state management (`saveState`, `restoreState`) and perturbation (`performKickMove`).
3.  New LSMC control parameters added to `DetailedParams`.
4.  A new, flexible `MultiObjective` engine defined in `MultiObjective.h` and `.cpp`.
5.  `DetailedMgr` will be refactored to construct and use this `MultiObjective` engine.
6.  All existing `DetailedGenerator` classes will be updated to use the `MultiObjective` engine for their cost evaluations.
7.  The main DPL entry point will be wired to call the new LSMC optimization loop.

This provides the core architectural overhaul. The engine will now be significantly more powerful at exploring the solution space and is architecturally prepared for the introduction of new, complex optimization objectives, which will be the focus of the subsequent implementation plan parts.


---

### **Implementation Plan Part 2: Advanced Objectives and Mixed-Cell-Height Support**

#### **I. High-Level Objective**

With the LSMC driver and Multi-Objective engine in place, this phase focuses on making the detailed placer "smarter" by teaching it about timing and advanced manufacturability rules. The goal is to leverage the new flexible architecture to address critical modern design closure challenges. This involves:

1.  **Implementing a Timing-Aware Objective:** Integrate a fast, conservative timing model (`Hippocrates` style) to allow the placer to reduce wirelength without degrading circuit performance.
2.  **Implementing a DFM-Aware Objective:** Create a framework for handling adjacency-based Design-for-Manufacturability (DFM) rules, using Drain-to-Drain Abutment (DDA) as the primary example.
3.  **Adding Mixed-Cell-Height Capability:** Implement a pragmatic "Transform and Conquer" pre- and post-processing methodology to enable the core engine to handle designs with multi-row height cells effectively.

These additions will be integrated as new objective "plug-ins" for the `MultiObjective` engine and as preparatory/refinement steps around the main LSMC optimization loop.

---

#### **II. Component 3: Implementation of the Timing-Aware Objective**

**(Inspired by `RenPANV07`'s "Hippocrates" methodology)**

This component introduces a `DetailedTimingObjective` class that enforces a "do no harm" constraint on circuit timing.

##### **A. Create New Files: `DetailedTimingObjective.h` and `DetailedTimingObjective.cpp`**

These files will be added to the `src/dpl/src/` directory.

*   **In `DetailedTimingObjective.h`:**
    ```cpp
    #pragma once

    #include "dpl/detailed_objective.h"
    #include "sta/Sta.hh" // For OpenSTA interface
    #include <unordered_map>

    // Forward declarations
    namespace odb { class dbITerm; }
    namespace dpl { class Network; class Grid; }

    namespace dpl {

    class DetailedTimingObjective : public DetailedObjective {
    public:
        DetailedTimingObjective(Network* network,
                                Grid* grid,
                                sta::Sta* sta,
                                utl::Logger* logger);

        // Perform one-time STA and pre-computation
        void initialize();

        // Overridden methods
        Cost curr() override;
        Cost delta(const Journal& journal) override;
        void accept(const Journal& journal) override;
        void reject(const Journal& journal) override;

    private:
        // Pre-computed timing budgets
        std::unordered_map<odb::dbITerm*, float> pin_arrival_time_budgets_;

        // Helper for delay estimation
        float estimateDelayChange(const Net* net, const DbuPt& old_src_pos, const DbuPt& new_src_pos);

        Network* network_;
        Grid* grid_;
        sta::Sta* sta_; // Pointer to the OpenROAD STA engine
        utl::Logger* logger_;

        bool initialized_ = false;
    };

    } // namespace dpl
    ```

*   **In `DetailedTimingObjective.cpp`:**
    *   **Constructor:** Store pointers to `Network`, `Grid`, `sta`, and `logger`.
    *   **`initialize()` Method:** This is the core pre-computation step.
        1.  Log a message indicating the start of timing pre-computation.
        2.  Ensure the STA engine (`sta_`) is up-to-date. It may be necessary to run `sta_->updateTiming(true)` or a similar command.
        3.  Iterate through every instance (`Node`) and its input pins (`odb::dbITerm`).
        4.  For each input pin, use the `sta_` API to query its arrival time (`AT_pin`) and the arrival time of its corresponding gate (`AT_gate`, which is the max AT over all input pins of that gate).
        5.  Calculate the budget: `budget = AT_gate - AT_pin`.
        6.  Store this budget in `pin_arrival_time_budgets_`.
        7.  Set `initialized_ = true;`
        8.  This method should be called once by `DetailedMgr` before the LSMC loop begins.
    *   **`delta()` Method:** This is the fast, local check performed for every potential move.
        1.  Check `if (!initialized_) { return 0.0; }`.
        2.  Iterate through each `JournalAction` in the `journal`.
        3.  For each moved cell, iterate through its output pins.
        4.  For each net connected to an output pin:
            a.  Calculate the change in wirelength/topology. A simple proxy is the change in the source pin's position.
            b.  Call `estimateDelayChange()` to get a `delta_delay` value. This function will use a simple, pre-characterized linear model (e.g., `delta_delay = K * delta_HPWL`) for speed.
            c.  For each sink pin on the net, retrieve its budget from `pin_arrival_time_budgets_`.
            d.  If `delta_delay > budget`, then this move violates the timing constraint. Immediately `return INFTY_COST;` (a very large number).
        5.  If the loops complete without any violation, `return 0.0;`. This signifies the move is timing-safe.
    *   **`curr()` Method:** Can return `0.0` as this objective is constraint-based, not a continuous cost to be minimized.
    *   **`accept()` / `reject()`:** These methods can be empty as the state is pre-computed and does not change during the optimization loop.

##### **B. Integration with `dpl::DetailedMgr`**

1.  **In `DetailedParams` (`detailed.h`):** Add a weight for the timing objective.
    ```cpp
    float timing_weight = 1.0; // By default, treat timing as a hard constraint.
    ```
2.  **In `DetailedMgr::buildObjectiveEngine()` (`detailed_manager.cpp`):**
    ```cpp
    void DetailedMgr::buildObjectiveEngine() {
        // ... (HPWL, displacement, etc. from Part 1) ...

        if (params_.timing_weight > 0) {
            auto timing_objective = std::make_unique<DetailedTimingObjective>(
                network_, grid_, sta_, logger_); // sta_ must be available in DetailedMgr
            timing_objective->initialize(); // Perform the one-time STA pre-computation
            multi_objective_engine_->addObjective(
                std::move(timing_objective), params_.timing_weight);
        }
    }
    ```
    *   **Note:** This requires that `DetailedMgr` has access to the top-level `sta::Sta` object. This might require passing it down from `Opendp` or the `dpl::Detailed` class constructor.

---

#### **III. Component 4: Implementation of the DFM-Aware Objective (DDA Example)**

**(Inspired by `DuW14`, `TsengC18`)**

This component provides a generic way to handle adjacency-based DFM rules.

##### **A. Create New Files: `DetailedDFMObjective.h` and `DetailedDFMObjective.cpp`**

*   **In `DetailedDFMObjective.h`:**
    ```cpp
    #pragma once

    #include "dpl/detailed_objective.h"
    #include <map>
    #include <tuple>

    namespace dpl {

    class DetailedDFMObjective : public DetailedObjective {
    public:
        // Enum for different rule types to support future expansion
        enum class DFMType { DDA };

        DetailedDFMObjective(Network* network, Grid* grid, utl::Logger* logger);

        void initialize(const std::vector<DFMType>& rules_to_check);

        // ... (overridden methods curr, delta, accept, reject) ...

    private:
        // State for a cell's boundary: Master pointer and orientation
        using BoundaryState = std::pair<const Master*, odb::dbOrientType>;
        // Key for the LUT: pair of adjacent boundary states
        using AdjacencyKey = std::pair<BoundaryState, BoundaryState>;
        // LUT storing the penalty for risky adjacencies
        std::map<AdjacencyKey, Cost> adjacency_penalties_;

        // Helper to compute penalty for a single cell's neighbors
        Cost computeAdjacencyCost(const Node* node) const;

        Network* network_;
        Grid* grid_;
        utl::Logger* logger_;
    };

    } // namespace dpl
    ```

*   **In `DetailedDFMObjective.cpp`:**
    *   **`initialize()` Method:**
        1.  Based on the `rules_to_check` vector, populate `adjacency_penalties_`.
        2.  For DDA:
            a.  Iterate through all pairs of `Master`s in `network_->getMasters()`.
            b.  For each pair (`masterA`, `masterB`), iterate through all valid orientations for each.
            c.  For each combination, check if placing them adjacently would cause a DDA violation. This requires access to the LEF definition to see if the boundary nodes are drains. (This may require a new helper utility to parse from `odb::dbMaster`).
            d.  If a violation exists, insert an entry into `adjacency_penalties_` with a high cost, e.g., `DDA_PENALTY`.
    *   **`computeAdjacencyCost()` Helper Method:**
        1.  Takes a `Node*` as input.
        2.  Finds its left and right neighbors on the `Grid`.
        3.  If neighbors exist, form `AdjacencyKey`s for `{left_neighbor, node}` and `{node, right_neighbor}`.
        4.  Look up these keys in `adjacency_penalties_`.
        5.  Return the sum of penalties found.
    *   **`delta()` Method:**
        1.  Initialize `total_delta = 0.0`.
        2.  For each moved cell in the `journal`, calculate its DFM cost in its **original** position using `computeAdjacencyCost()` and subtract it from `total_delta`.
        3.  Calculate its DFM cost in its **new** position using `computeAdjacencyCost()` and add it to `total_delta`.
        4.  This correctly computes the net change in DFM cost.
    *   **`curr()` Method:**
        1.  Iterate through all movable cells.
        2.  For each cell, call `computeAdjacencyCost()` and sum the results.
        3.  Divide the final sum by 2 (since each adjacency is counted twice).

##### **B. Integration with `dpl::DetailedMgr`**

*   This follows the same pattern as the timing objective. Add a `dfm_weight` to `DetailedParams` and update `DetailedMgr::buildObjectiveEngine()` to construct and add a `DetailedDFMObjective` instance to the `MultiObjective` engine.

---

#### **IV. Component 5: Pragmatic Mixed-Cell-Height Support**

**(Inspired by `WuC16`)**

This is implemented as a manager class that wraps the main optimization flow.

##### **A. Create New Files: `MixedHeightManager.h` and `MixedHeightManager.cpp`**

*   **In `MixedHeightManager.h`:**
    ```cpp
    #pragma once

    namespace dpl {

    class DetailedMgr;
    class Network;

    class MixedHeightManager {
    public:
        MixedHeightManager(DetailedMgr* mgr, Network* network, /* ... other needed objects */);

        // Main entry point
        void run();

    private:
        void prepare(); // Cell pairing and expansion
        void refine();  // Unpair, deflate, and refine single-row cells

        struct MatchedPair { /* ... */ };
        std::vector<MatchedPair> selected_pairs_;
        std::vector<Node*> expanded_cells_;

        DetailedMgr* mgr_;
        Network* network_;
        // ...
    };

    } // namespace dpl
    ```

*   **In `MixedHeightManager.cpp`:**
    *   **`prepare()` Method:**
        1.  Identify all single-row (`SRH`) and multi-row (`MRH`) cells. If no MRH cells exist, this manager does nothing.
        2.  Construct a sparse matching graph for all SRH cells (neighbors within a certain radius).
        3.  Calculate edge weights based on connectivity and proximity, as described in `WuC16`.
        4.  Run a greedy maximum weighted matching algorithm to find candidate pairs.
        5.  Perform density-aware pair selection:
            a.  For each placement bin, calculate the current utilization.
            b.  Decide which matched pairs within that bin to "finalize" based on a heuristic that tries to create free space in dense bins while preserving placement flexibility in sparse bins.
            c.  For finalized pairs, create a new "pseudo-cell" or `Node` representing the merged pair. Deactivate the original two cells.
        6.  For all remaining, unpaired SRH cells, "expand" them by changing their `height_` property and updating their footprint logic so the placer treats them as MRH cells.
    *   **`run()` Method:**
        1.  Call `prepare()`.
        2.  Call `mgr_->runLSMCOptimization()`. The DPL engine now operates on a uniform-height design.
        3.  Call `refine()`.
    *   **`refine()` Method:**
        1.  Fix the positions of all original MRH cells and newly formed paired cells (`node->setFixed(true)`).
        2.  "Deflate" the expanded cells back to their original SRH height. "Unpair" the paired cells back into their two original SRH constituents, placing them legally within the footprint of their parent pair.
        3.  Run a final, brief optimization pass (e.g., `mgr_->runGenerator(...)` for a few iterations) targeting *only* the now-freed SRH cells.

##### **B. Top-Level Integration**

The main `Opendp::detailedPlacement()` function will now instantiate `MixedHeightManager` and call its `run()` method, instead of directly calling the `DetailedMgr`'s optimization loop. The `MixedHeightManager` will orchestrate the entire process.

---

#### **V. Summary of Part 2 Deliverables**

Upon completion of this part, the DPL engine will be equipped with:

1.  A fully functional **`DetailedTimingObjective`**, enabling timing-aware placement by enforcing pre-computed timing budgets.
2.  A generic **`DetailedDFMObjective`** framework, with an initial implementation for DDA, allowing the placer to mitigate manufacturability issues.
3.  Both new objectives will be seamlessly integrated into the `MultiObjective` engine from Part 1.
4.  A **`MixedHeightManager`** that enables robust and effective detailed placement for complex mixed-cell-height designs by transforming the problem for the core engine.

The detailed placer will have evolved from a simple geometric optimizer into a sophisticated, multi-objective design closure tool, capable of tackling the key challenges of modern physical design.


---

### **Implementation Plan Part 3: Strengthening Core Algorithms and Utilities**

#### **I. High-Level Objective**

The goal of this phase is to upgrade the fundamental "move generation" and "legalization" capabilities of the DPL engine. A powerful metaheuristic like LSMC is only as good as the local search it directs. This part will focus on making the core placement operators faster, more effective, and fully compatible with the new multi-objective, mixed-height, and DFM-aware ecosystem. This includes:

1.  **Upgrading the Single-Row Placement Engine:** Implement a state-of-the-art, linear-time optimal single-row placer. This will serve as a high-speed, high-quality utility for legalization and refinement.
2.  **Introducing an "Instant Legalization" Paradigm:** Integrate the new single-row placer into a fast, local legalizer that enables more aggressive and exploratory moves by providing a safety net.
3.  **Enhancing Core Optimization Generators:** Make the existing generators (`DetailedGlobalSwap`, `DetailedReorderer`, `DetailedMis`) fully aware of the new multi-objective framework and the complexities of mixed-height designs.

---

#### **II. Component 6: Upgrading the Single-Row Placement Engine**

**(Inspired by `SpindlerSJ08`, `KahngTZ99`, `LinYZLAP16`)**

A fast and optimal single-row placer is a cornerstone utility for any modern detailed placer. It is used for final legalization, compaction, and as a subroutine in more complex moves. The current DPL likely has a functional but potentially suboptimal implementation. We will replace it with an engine based on the `Abacus`/`Clumping` algorithm, enhanced with a state-of-the-art pruning technique.

##### **A. Create a New Utility Class: `SingleRowOptimizer`**

This will be a self-contained class in `src/dpl/src/` (e.g., `SingleRowOptimizer.h`, `SingleRowOptimizer.cpp`).

*   **In `SingleRowOptimizer.h`:**
    ```cpp
    #pragma once

    #include <vector>
    #include "dpl/Objects.h" // For Node
    #include "dpl/detailed_objective.h" // For Cost

    namespace dpl {

    class SingleRowOptimizer {
    public:
        SingleRowOptimizer(const std::vector<Node*>& cells_in_row,
                           const odb::Rect& row_bounds);

        // Main entry point. Optimizes cell positions within the row.
        // The objective can be configured for displacement, HPWL, etc.
        // Returns true on success.
        bool optimize();

        // After optimization, retrieve the final positions.
        const std::vector<DbuPt>& getFinalPositions() const;

    private:
        struct Cluster {
            int start_cell_idx;
            int end_cell_idx;
            DbuX total_width;
            DbuX optimal_pos; // Left boundary of the cluster
            // ... other aggregated properties for cost calculation
        };

        // Core DP / clumping logic
        void collapseClusters(int cluster_idx);
        void calculateOptimalClusterPos(Cluster& cluster);

        const std::vector<Node*>& cells_;
        const odb::Rect& row_bounds_;
        std::vector<Cluster> clusters_;
        std::vector<DbuPt> final_positions_;
    };

    } // namespace dpl
    ```

*   **In `SingleRowOptimizer.cpp`:**
    *   **Implement the `Abacus`-style Dynamic Programming / Clumping Algorithm:**
        1.  The `optimize()` method will iterate through the `cells_` vector.
        2.  For each cell, it creates a single-cell `Cluster`.
        3.  `calculateOptimalClusterPos()` will be implemented. For a simple displacement objective, this is the weighted average of the cells' original positions. For HPWL, this is more complex, requiring finding the median of the "minimum intervals" as described in `KahngTZ99`.
        4.  After placing a new cluster, check for overlap with the previous one. If they overlap, merge them into a new, larger cluster (`collapseClusters`) and recursively check for overlaps with the preceding cluster.
        5.  This process continues until all cells are grouped into non-overlapping clusters.
        6.  Finally, iterate through the final clusters and calculate the exact `final_positions_` for each cell within them.
    *   **Incorporate `O(nM)` Pruning (Advanced):** While the `Abacus` clumping is `O(N)`, a more general DP formulation can handle more complex, non-convex costs. If a DP table approach is used, the `O(nM)` pruning from `LinYZLAP16` (pruning inferior solutions and monotonic search space) should be implemented to ensure scalability. For the initial implementation, the `O(N)` clumping for convex objectives is sufficient and powerful.

---

#### **III. Component 7: Implementing an "Instant Legalization" Utility**

**(Inspired by `PopovychLWLLW14`'s BraveDP)**

This component provides a critical safety net that enables more aggressive optimization strategies. It's a fast, local legalizer that is called *immediately* after a potentially illegal move (like a swap of different-sized cells).

##### **A. Create a `LocalLegalizer` Class**

This can be a new class or a set of functions within `DetailedMgr.cpp`.

*   **`legalizeAroundCell(Node* target_cell)` Method:**
    *   **Input:** A `target_cell` that has just been moved, potentially creating overlaps with its new neighbors.
    *   **Process:**
        1.  **Identify Affected Segment:** Determine the contiguous segment of cells in the `target_cell`'s row that are now overlapping or immediately adjacent. This defines the local sub-problem.
        2.  **Invoke `SingleRowOptimizer`:** Instantiate the new `SingleRowOptimizer` with the cells in this affected segment.
        3.  **Run Optimization:** Call `optimize()` on the `SingleRowOptimizer` with a **minimum displacement objective**. This will resolve the overlaps with the smallest possible total movement for the local group of cells.
        4.  **Update Placement:** Update the positions of the affected cells and their footprints on the `Grid` based on the result from the optimizer.

##### **B. Integration into `DetailedGenerator`s and the LSMC Loop**

The true power of this utility comes from its integration.

*   **Modify `DetailedGlobalSwap` and other generators:**
    *   After a beneficial swap is identified (e.g., swapping cells of different sizes), the generator will:
        1.  **Execute the swap tentatively** (e.g., using the `Journal`).
        2.  **Call `local_legalizer->legalizeAroundCell()`** on both swapped cells' locations to resolve any new overlaps. This will also update the `Journal` with the subsequent legalization moves.
        3.  **Evaluate the *true* cost:** Now, with a fully legal (but perturbed) state, call `multi_objective_engine_->delta(journal)`. This gives the *actual* cost of the swap *plus* its legalization ripple effect.
        4.  **Accept/Reject:** If this true cost is acceptable, `accept` the journal.
        5.  **Revert:** If not, `reject` the journal. The `Journal`'s undo capability will efficiently revert both the initial swap and all the legalization moves, returning the placement to its original state.
*   **Benefits:**
    *   Allows for much more powerful moves (e.g., swapping a large cell into a region of smaller cells).
    *   Provides accurate cost evaluation, preventing the optimizer from making moves that look good pre-legalization but are disastrous afterward.
    *   Trivially enforces constraints like maximum displacement. If the legalization ripple pushes any cell beyond its limit, the entire move can be rejected.

---

#### **IV. Component 8: Enhancing Core Optimization Generators**

The existing generators must be updated to be fully aware of the new architectural components.

##### **A. `DetailedGlobalSwap` (`detailed_global.h`, `.cpp`)**

*   **Mixed-Height Awareness:**
    *   When the `MixedHeightManager` is active, the generator will operate on the transformed, uniform-height design.
    *   When not active (or during the final refinement pass), the legality check for a swap must be enhanced. A multi-row cell can only be swapped to a location that has the correct number of consecutive, available rows with compatible site types and power rail alignments. The `Grid` and `Architecture` classes provide the necessary information for this check.
*   **Integration with Instant Legalization:** As described above, `DetailedGlobalSwap` will now use the `LocalLegalizer` to handle swaps of different-sized cells, allowing for a much richer set of possible moves.

##### **B. `DetailedReorderer` (`detailed_reorder.h`, `.cpp`)**

*   **DFM and Timing Awareness:** The reordering algorithm (which explores permutations in a window) needs to be enhanced to handle more complex states.
    *   **State Expansion:** When evaluating permutations, the state of a cell is not just its position but also its orientation (flip). In a future DFM-aware version (e.g., for TPL), it could also include a color assignment.
    *   **Cost Function:** The `cost()` function within the reorderer, which currently likely just calculates HPWL, must be replaced with a call to `multi_objective_engine_->delta()`. This will allow it to optimize for the full weighted sum of HPWL, timing, and DFM penalties simultaneously.
    *   **Example:** When evaluating a permutation, it will now check for DDA violations between the newly adjacent cells and include the DFM penalty in the total cost of that permutation.
*   **Mixed-Height Handling:** Reordering windows that contain multi-row cells is complex. The initial implementation should treat multi-row cells as boundaries for the reordering window, only reordering the single-row cells between them. A more advanced implementation could use a graph-based DP approach (like in `LinYXP17`) to handle reordering multi-row cells as well.

##### **C. `DetailedMis` (`detailed_mis.h`, `.cpp`)**

*   This generator performs local optimization on small clusters of cells. It is a powerful technique that can be adapted.
*   **Objective Function:** The internal Branch & Bound solver (`solveMatch`) must be modified to use the `multi_objective_engine_` to evaluate the cost of a partial or complete assignment of cells to locations.
*   **Constraint Checking:** The legality checks within `solveMatch` must be updated to handle multi-row cells and their specific placement constraints (row spanning, power rail alignment).

---

#### **V. Summary of Part 3 Deliverables**

Upon completion of this part, the DPL engine's core capabilities will be significantly strengthened:

1.  A new, fast, and optimal **`SingleRowOptimizer`** utility will be available for high-quality, fixed-order row placement.
2.  An **"Instant Legalization"** framework will be integrated with the move generators, enabling more powerful and exploratory optimization moves while maintaining placement legality.
3.  The core optimization generators (`GlobalSwap`, `Reorderer`, `Mis`) will be made fully aware of the **`MultiObjective` engine**, allowing them to intelligently trade off between wirelength, timing, and DFM.
4.  The generators will also have enhanced logic to correctly and legally handle **mixed-cell-height designs**.

With these three parts implemented, the OpenROAD DPL will have undergone a complete transformation. It will be driven by a state-of-the-art search metaheuristic (LSMC), guided by a flexible and modern multi-objective cost function, and powered by robust, efficient, and constraint-aware core placement algorithms. This will position it as a leading-edge, open-source detailed placer capable of addressing the full spectrum of challenges in modern VLSI design.