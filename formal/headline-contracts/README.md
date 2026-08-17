# Lean contracts for the three headline patch families

These modules formalize selected mathematical kernels corresponding to the routed-wirelength, ECP, and power patch families. They do **not** model full OpenROAD C++ semantics and do not prove global QoR improvement.

| Module | Patch family | Main obligations | Theorems | `sorry` |
|---|---|---|---:|---:|
| `OpenRoadWlFull.lean` | DPL two-pass congestion-aware swap | `[0,1]` normalization, positive accepted profit, HPWL budget preservation, pass-one behavior | 68 | 0 |
| `OpenRoadEcpFull.lean` | GPL timing weights + RSZ repair | weight bounds/monotonicity, WNS-preserving repair, nonempty fallback | 50 | 0 |
| `OpenRoadPwrFull.lean` | RSZ instance-ranked recovery | fraction/score bounds, timing/DRV guards, decreasing-area commits, termination | 49 | 0 |

## Local check

With Lean/Lake available:

```bash
lake update
lake build
```

The pinned toolchain and Mathlib revision are in `lean-toolchain` and `lakefile.toml`.

## Claim boundary

The broader S4 guard layer scans all 100 final-audit candidates. Seventy-one candidates admit at least one domain-specific range, monotonicity, or secondary-objective obligation; only the three headline families have full Lean modules here. The separate timing-clamp manifest remains under `../lean-artifacts/`.
