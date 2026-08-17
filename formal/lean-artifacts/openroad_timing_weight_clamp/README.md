# OpenROAD Timing Weight Clamp

This case packages a real OpenROAD C++ patch together with the Lean artifacts used to formalize and verify its intended bound.

The patch changes two things in `src/gpl/src/timingBase.cpp`:

- it clamps `net_weight_max_` so the configured maximum is never below `1.0`
- it clamps the computed timing weight into `[1, net_weight_max_]`

The Lean side models that behavior over `Real` and proves that the resulting `timingWeight` stays inside those bounds.

## Folder layout

- `patch/openroad_timing_weight_clamp.patch`: the actual OpenROAD diff.
- `manifest/openroad_timing_weight_clamp.json`: binds the OpenROAD base commit, patch, statement, and proof.
- `lean_contract/openroad_timing_weight.statement.lean`: the contract with `sorry` placeholders.
- `lean_contract/openroad_timing_weight.proof.lean`: the discharged proof checked by the formal gate.
- `aristotle_input/OpenRoadTimingWeight.lean`: the pre-repair Lean file submitted for proof repair.
- `aristotle_output/OpenRoadTimingWeight.lean`: the repaired Lean file returned by Aristotle.
- `aristotle_output/ARISTOTLE_SUMMARY.md`: short summary of the repair.
- `aristotle_output/REPAIR_DIFF.diff`: direct diff between the Aristotle input and output files.
- `aristotle_output/lakefile.toml`, `aristotle_output/lean-toolchain`, `aristotle_output/lake-manifest.json`: project metadata from the repaired Lean project.

## Artifact flow

1. Apply or sanity-check the OpenROAD patch.
2. Use the manifest to bind that patch to a Lean statement/proof pair.
3. Verify the proof against the statement with the formal gate.
4. Compare the Aristotle input and output files to see the proof-repair step.

## Verification

From the repo root:

```bash
python3 formal/formal_gate.py verify-manifest \
  --manifest formal/lean-artifacts/openroad_timing_weight_clamp/manifest/openroad_timing_weight_clamp.json
```

This requires `AXLE_API_KEY`. The manifest points at the OpenROAD checkout under `formal/openroad`.

If Lean/Lake is installed locally, you can also build the repaired project directly:

```bash
cd formal/lean-artifacts/openroad_timing_weight_clamp/aristotle_output
lake build
```

Re-running Aristotle itself is optional and requires `ARISTOTLE_API_KEY`.
