# Execution Plan for Task: Power- and Timing-Aware Multi-Bit Flip-Flop (MBFF) Synthesis for Sink Clustering

Here is the execution plan for integrating power- and timing-aware Multi-Bit Flip-Flop (MBFF) synthesis into TritonCTS.

### 1. Configuration and Options

New parameters will be added to control the MBFF synthesis feature.

**File: `src/cts/src/CtsOptions.h`**
```diff
--- a/src/cts/src/CtsOptions.h
+++ b/src/cts/src/CtsOptions.h
@@ -65,6 +65,16 @@
   unsigned _sinkClustersBlockSize = 200;
   unsigned _sinkClustersMaxDiameter = 0;
   unsigned _sinkClustersMinSinks = 2;
+
+  // MBFF synthesis options
+  bool _enableMbffSynthesis = false;
+  float _mbffPowerWeight = 1.0;
+  float _mbffDisplacementWeight = 1.0;
+  float _mbffTimingWeight = 1.0;
+  unsigned _mbffMaxDisplacementMicrons = 10;
 
   // Metrics
   unsigned _numSinks = 0;

@@ -141,6 +151,12 @@
   void setSinkClustersMinSinks(unsigned minSinks) { _sinkClustersMinSinks = minSinks; }
   unsigned getSinkClustersMinSinks() const { return _sinkClustersMinSinks; }
 
+  void setEnableMbffSynthesis(bool enable) { _enableMbffSynthesis = enable; }
+  bool getEnableMbffSynthesis() const { return _enableMbffSynthesis; }
+  void setMbffPowerWeight(float weight) { _mbffPowerWeight = weight; }
+  void setMbffDisplacementWeight(float weight) { _mbffDisplacementWeight = weight; }
+  void setMbffTimingWeight(float weight) { _mbffTimingWeight = weight; }
+
  private:
   void copy(const CtsOptions& other);
 };

```

### 2. Main CTS Flow Integration

The top-level TritonCTS driver will be modified to invoke the new flow based on the configuration.

**File: `src/cts/src/TritonCTS.cpp`**
```diff
--- a/src/cts/src/TritonCTS.cpp
+++ b/src/cts/src/TritonCTS.cpp
@@ -103,7 +103,12 @@
   // Cluster sinks
   _sinkClustering->run();
 
-  // Build clock trees
+  // If MBFF synthesis is enabled, it will have been run inside _sinkClustering->run().
+  // The netlist is now modified with MBFFs, and the sink list is updated.
+  // The flow can now proceed to build the clock tree with the new set of sinks.
+
+  // Build clock tree
   _htreeBuilder->run();
 
   // Write metrics
```

### 3. Sink Clustering and ILP Formulation

The core logic will reside in `SinkClustering.cpp`. It will be structured to either run the existing geometric/k-means clustering or the new ILP-based MBFF synthesis.

**File: `src/cts/src/SinkClustering.cpp`**
```diff
--- a/src/cts/src/SinkClustering.cpp
+++ b/src/cts/src/SinkClustering.cpp
@@ -21,6 +21,8 @@
 #include "TritonCTS.h"
 #include "sta/Liberty.hh"
 #include "utl/Logger.h"
+// Include for ILP solver (e.g., Cbc, lpsolve)
+// #include "ilp/IlpSolver.h"
 
 namespace cts {
 
@@ -31,10 +33,18 @@
 
 void SinkClustering::run()
 {
-  if (_options->getSinkClusteringTechnique() == K_MEANS) {
-    runKMeans();
-  } else {
-    runGeometric();
+  if (_options->getEnableMbffSynthesis()) {
+    runMbffSynthesis();
+  } else {
+    if (_options->getSinkClusteringTechnique() == K_MEANS) {
+      runKMeans();
+    } else {
+      runGeometric();
+    }
   }
 }
 
+void SinkClustering::runMbffSynthesis()
+{
+  // 1. Identify candidate single-bit flip-flops from the clock network sinks.
+  collectCandidateSinks();
+
+  // 2. Find compatible MBFF cells from the technology library (.lib).
+  //    - Query db for masters with FF functionality and multiple bits.
+  //    - Store properties like bit-count, power, size.
+  findLibraryMbffs();
+
+  // 3. Divide-and-conquer: Partition sinks into manageable sub-problems
+  //    based on proximity to reduce ILP complexity.
+  auto subProblems = partitionSinks();
+
+  // 4. For each sub-problem, formulate and solve the ILP.
+  for (auto& problem : subProblems) {
+    formulateAndSolveIlp(problem);
+  }
+
+  // 5. Post-process the results.
+  //    - Instantiate the new MBFF cells in the netlist.
+  //    - Remove the original single-bit FFs.
+  //    - Update the internal sink data structure for HTreeBuilder.
+  applyClusteringSolution();
+}
+
+void SinkClustering::formulateAndSolveIlp(const SubProblem& problem)
+{
+  // This is the core of the new feature.
+  // A. Initialize ILP Solver instance.
+
+  // B. Define variables:
+  //    - Binary variable x_ij for each single-bit FF 'i' and each potential MBFF cluster 'j'.
+  //    - x_ij = 1 if FF 'i' is assigned to cluster 'j', 0 otherwise.
+
+  // C. Define Objective Function:
+  //    - Minimize: Sum(Power_j * y_j) * w_power +
+  //                Sum(Displacement_ij * x_ij) * w_displacement +
+  //                Sum(TimingDivergence_j * y_j) * w_timing
+  //    - Where y_j is a variable indicating if cluster 'j' is created.
+  //    - Power_j is the power of the MBFF used for cluster 'j'.
+  //    - Displacement_ij is the distance from FF 'i' to the location of cluster 'j'.
+  //    - TimingDivergence_j is a metric for timing path differences for FFs in cluster 'j'.
+
+  // D. Define Constraints:
+  //    - Each FF 'i' can be assigned to at most one cluster 'j'. (Sum_j(x_ij) <= 1)
+  //    - The number of FFs in a cluster 'j' cannot exceed the bit-count of the chosen MBFF.
+  //    - The placement location of cluster 'j' must be legal.
+  //    - Max displacement constraint.
+
+  // E. Solve the ILP problem.
+
+  // F. Store the solution (mapping of FFs to MBFFs).
+}
+
+void SinkClustering::applyClusteringSolution()
+{
+  // Iterate through the ILP solution.
+  // For each new MBFF cluster:
+  //  1. Get the list of single-bit FFs to be replaced.
+  //  2. Choose the best MBFF master from the library for this cluster size.
+  //  3. Create a new dbInst for the MBFF.
+  //  4. Place the new instance at the computed optimal location (e.g., centroid).
+  //  5. Disconnect clock and data pins of the old FFs.
+  //  6. Connect the new MBFF's clock pin to the clock net.
+  //  7. Reconnect the data paths (D, Q) to the appropriate bits of the new MBFF.
+  //  8. Delete the old FF instances.
+  //  9. Create a new 'ClockInst' for the MBFF and add it to the clock's sink list.
+  //  10. Remove the old FFs from the clock's sink list.
+}
+
 // ... existing runKMeans() and runGeometric() methods ...
 
 }  // namespace cts
```

### 4. Documentation Updates

**File: `TritonCTS.md` (or relevant documentation)**

*   **Add a new section: "Power and Timing-Aware MBFF Synthesis"**
    *   Describe the goal of the feature: to reduce clock power and area by intelligently clustering flip-flops into multi-bit equivalents.
    *   Explain the ILP-based methodology, contrasting it with purely geometric clustering. Mention that it considers power, placement location, and timing divergence.
    *   Detail the new Tcl commands and parameters.
*   **Update the parameter table:**
    *   `cts.enable_mbff_synthesis` (Boolean): Enables or disables the MBFF synthesis flow. When enabled, it replaces the standard sink clustering step. Default: `false`.
    *   `cts.mbff_power_weight` (Float): Sets the weight for the power component in the ILP cost function. Default: `1.0`.
    *   `cts.mbff_displacement_weight` (Float): Sets the weight for the placement displacement component in the ILP cost function. Default: `1.0`.
    *   `cts.mbff_timing_weight` (Float): Sets the weight for the timing path divergence component in the ILP cost function. Default: `1.0`.
    *   `cts.mbff_max_displacement_microns` (Integer): Sets the maximum allowed distance a single-bit FF can be moved to form an MBFF cluster. Default: `10`.