```markdown
# Proposal: Power- and Timing-Aware Multi-Bit Flip-Flop (MBFF) Synthesis for Sink Clustering

## 1. Abstract

This document proposes the integration of a power- and timing-aware Multi-Bit Flip-Flop (MBFF) synthesis capability into the sink clustering stage of TritonCTS. The current geometric and k-means clustering heuristics will be augmented with an optimization-based methodology. This approach employs a divide-and-conquer strategy, utilizing an Integer Linear Program (ILP) solver to map single-bit flip-flops to functionally equivalent MBFFs from the technology library. The objective is to concurrently minimize clock network power, placement displacement, and timing-path divergence.

## 2. High-Level Architectural Modification

The MBFF synthesis will be introduced as an optional, advanced sink clustering stage preceding the `HTreeBuilder`.

**Current Flow:**
`Sink Discovery -> Sink Clustering (Geometric/K-Means) -> HTreeBuilder -> LevelBalancer`

**Proposed Flow (when enabled):**
`Sink Discovery -> MBFF Synthesis (ILP-based Clustering) -> HTreeBuilder -> LevelBalancer`

The MBFF Synthesis stage will consume the initial list of flip-flop sinks and produce a reduced set of sinks corresponding to the clock pins of the synthesized MBFF instances. The `HTreeBuilder` will subsequently construct a clock tree based on this power-optimized sink distribution.

## 3. Component-Level Design

### 3.1. New Component: `MbffLibrary`

An `MbffLibrary` component will be introduced to abstract the properties of available MBFF cells from the technology library. This component is a prerequisite for the ILP formulation.

**Interface Definition:** `src/cts/src/MbffLibrary.h`
```cpp
#pragma once

#include <string>
#include <vector>
#include "odb/db.h"

namespace cts {

struct MbffCellInfo {
    std::string name;
    odb::dbMaster* master = nullptr;
    int bit_count = 0;
    int width = 0;
    int height = 0;
    std::string clock_pin_name;
    double clock_pin_capacitance = 0.0;
    // Relative location of the clock pin within the cell
    Point<int> clock_pin_location;
};

class MbffLibrary {
public:
    MbffLibrary(odb::dbDatabase* db, utl::Logger* logger);
    void parse();
    const std::vector<MbffCellInfo>& getMbffs() const { return mbffs_; }

private:
    odb::dbDatabase* db_;
    utl::Logger* logger_;
    std::vector<MbffCellInfo> mbffs_;
};

}
```

**Implementation Details:** `src/cts/src/MbffLibrary.cpp`
The `parse()` method will iterate through all `dbMaster` objects in the database. It will identify MBFF cells (masters of type `dbMasterType::FF`) and extract the following properties for each:
- **Bit Count**: Determined from the number of primary output pins or specific Liberty attributes.
- **Physical Dimensions**: Width and height from the master's bounding box.
- **Clock Pin Properties**: The name, input capacitance, and relative physical location of the master's clock pin.

This library will be instantiated once and passed to the clustering engine.

### 3.2. New Component: `MbffClusteringEngine`

This component will implement the core recursive, ILP-based clustering algorithm.

**Interface Definition:** `src/cts/src/MbffClusteringEngine.h`
```cpp
#pragma once

#include "Clock.h"
#include "CtsOptions.h"
#include "MbffLibrary.h"

namespace cts {

class MbffClusteringEngine {
public:
    MbffClusteringEngine(CtsOptions* options, 
                         Clock& clock,
                         const MbffLibrary& mbff_lib,
                         sta::dbSta* sta);

    // Main entry point
    void run();

private:
    void recursivePartitionAndSolve(const std::vector<ClockInst*>& sinks, const Box<int>& region);
    void formulateAndSolveIlp(const std::vector<ClockInst*>& sinks, const Box<int>& region);
    std::vector<std::pair<ClockInst*, ClockInst*>> getLaunchCapturePairs(const std::vector<ClockInst*>& sinks);

    CtsOptions* options_;
    Clock& clock_;
    const MbffLibrary& mbff_lib_;
    sta::dbSta* sta_;
    std::vector<ClockInst*> new_sinks_; // Stores the resulting MBFF instances
};

}
```

**Implementation Details:** `src/cts/src/MbffClusteringEngine.cpp`
- **`run()`**: The main entry point, which retrieves the initial flip-flop sinks and initiates the recursive partitioning process on the entire design area.
- **`recursivePartitionAndSolve()`**: Implements a divide-and-conquer strategy.
  - **Base Case**: If the sink count within the current region is below a defined threshold (e.g., 256), `formulateAndSolveIlp()` is invoked.
  - **Recursive Step**: If the sink count exceeds the threshold, the region is bisected, and the sinks are partitioned accordingly. The function then makes two recursive calls for the resulting sub-problems.
- **`getLaunchCapturePairs()`**: Queries the static timing analyzer (`sta_`) to identify all sequential launch-capture timing paths among the sinks within the current partition. This data is required for the timing-divergence term in the ILP objective function.
- **`formulateAndSolveIlp()`**: Formulates and solves the local MBFF mapping problem using an integrated ILP solver.

### 3.3. ILP Formulation

For each partition, the following ILP problem will be solved.

**Inputs:**
- `F`: Set of single-bit flip-flops in the partition.
- `M`: Set of available MBFF master cells from `MbffLibrary`.
- `L`: Set of launch-capture pairs `(f_launch, f_capture)` where `f_launch, f_capture` are in `F`.
- `α, β`: User-defined weighting coefficients.

**Variables:**
- `x_fk`: Binary variable, equal to 1 if flip-flop `f ∈ F` is assigned to MBFF instance `k`.
- `y_mk`: Binary variable, equal to 1 if MBFF instance `k` of master type `m ∈ M` is utilized.
- `pos_k`: Continuous variable representing the (x, y) coordinates of MBFF instance `k`.

**Objective Function:**
Minimize a weighted sum of power, placement displacement, and timing-path divergence.
`minimize(α * W + D + β * R)`
where:
- **Power Term (W)**: `Σ (y_mk * m.clock_pin_capacitance)` for all `m ∈ M` and instances `k`.
- **Displacement Term (D)**: `Σ (x_fk * manhattan_dist(f.location, pos_k))` for all `f ∈ F` and instances `k`.
- **Divergence Term (R)**: `Σ manhattan_dist(pos_k1, pos_k2)` for all pairs `(f1, f2) ∈ L`, where `f1` is mapped to instance `k1` and `f2` is mapped to instance `k2`.

**Constraints:**
1.  **Assignment Constraint**: Each flip-flop must be assigned to exactly one MBFF instance.
    `∀ f ∈ F: Σ (x_fk over all instances k) = 1`
2.  **Capacity Constraint**: The number of flip-flops assigned to an MBFF instance cannot exceed its bit count.
    `∀ instances k of type m: Σ (x_fk over all f ∈ F) ≤ m.bit_count * y_mk`
3.  **Placement Constraint**: The location of each MBFF instance must be within the partition's bounding box.
    `∀ instances k: region.min ≤ pos_k ≤ region.max`

Upon solving, new `ClockInst` objects are created for each utilized MBFF (`y_mk = 1`) and added to the list of new clock sinks.

## 4. Modifications to Existing System

### 4.1. `CtsOptions`
The `CtsOptions` class will be extended with parameters to control the feature.
- `mbffSynthesisEnable_` (bool): Enables or disables the MBFF synthesis flow.
- `mbffAlpha_` (double): The weight `α` for the power term in the ILP objective function.
- `mbffBeta_` (double): The weight `β` for the timing-divergence term in the ILP objective function.

### 4.2. Scripting Interface
The Tcl scripting interface will be extended to expose the new options.
```tcl
# In clock_tree_synthesis Tcl command
sta::parse_key_args "clock_tree_synthesis" args \
    ... \
    -mbff_synthesis_enable      -bool \
    -mbff_alpha                 -float \
    -mbff_beta                  -float
```
Corresponding setters will be exposed via SWIG in `TritonCTS.i` to connect the Tcl commands to the C++ `CtsOptions` object.

### 4.3. `TritonCTS.cpp` Orchestration
The main `runTritonCts()` method will be modified to conditionally execute the new flow.
```cpp
// In TritonCTS::runTritonCts()
MbffLibrary mbff_lib(db_, logger_);
mbff_lib.parse();

// In buildClockTrees() loop
if (options_->getMbffSynthesisEnable()) {
    MbffClusteringEngine mbff_engine(options_, clock, mbff_lib, openSta_);
    mbff_engine.run();
    // The engine will replace the sinks in the 'clock' object.
}
// The existing HTreeBuilder flow proceeds with the (potentially modified) sink list.
```

### 4.4. `Clock` Class
A new method will be added to the `Clock` class to replace the original sinks with the newly synthesized MBFF instances.
```cpp
// In Clock.h
public:
    void setSinks(const std::vector<ClockInst*>& new_sinks);
```
This method will clear the existing sink list and internal maps, then populate them with the provided list of new sinks.

## 5. Build System Integration

The `CMakeLists.txt` file for the `cts` module will be updated:
1.  An open-source ILP solver library (e.g., Cbc, GLPK) will be added as a dependency via `find_package`.
2.  The new source files (`MbffLibrary.cpp`, `MbffClusteringEngine.cpp`) will be added to the `cts_lib` target.
3.  The `cts_lib` target will be linked against the ILP solver library.

## 6. Verification and Debugging Support

The `CtsGraphics` component will be enhanced to support debugging of the MBFF synthesis flow. A new visualization mode will be implemented to display the recursive partition boundaries. Within each partition, the GUI will render the locations of the original flip-flops and the final, optimized locations of the MBFF instances to which they were mapped. This will provide visual feedback on the partitioning and placement results generated by the ILP solver.
```