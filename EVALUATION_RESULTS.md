# Evaluation results

The measurements below use the pinned OpenROAD/ORFS evaluation snapshot
described in [`README.md`](README.md) and [`diffs/README.md`](diffs/README.md).
The linked Lean modules formalize scoped local invariants for the three patch
families.

| Topic | Result |
|---|---|
| Matched tuner | Across SKY130HD `aes`, Nangate45 `aes`, and ASAP7 `jpeg`, the reusable source diff is 2.11% lower in routed wirelength on average than the time/compute-matched tuned result. |
| Final audit | 92/100 final-signoff primary-objective wins (33/36 rWL, 28/30 ECP, 31/34 power); aggregate median 3.95%, mean 5.40%, and 95% binomial win-rate interval 85.0–95.9%. |
| Robustness | The 404-point 1-ps ECP sweep gives mean 4.80%, standard deviation 2.90%, and 95% CI 4.52–5.08%; the 12 numerical rWL rows give mean 2.13% and 95% CI 0.60–3.66%. |
| Stage/context ablations | Removing S0/S1/S2/S3/S4 gives 44/26/37/54/41 wins; repository+literature/repository-only/literature-only/long-context/static-context/no-retrieval gives 92/71/39/55/48/26 wins. |
| Power/ECP frontier | Power falls in 26/27 public design/library points (median 6.525%); median reductions are 3.4%, 6.2%, and 9.1% under ±0.5%, 2%, and 5% ECP budgets. |
| Public ECP scope | The same ECP diff improves Nangate45 `mempool_group` by 2.01% and ASAP7 `riscv32i` by 2.86% at 70% TCP (1.61% at 85% TCP). |
| Proxy fidelity | Of 38 CI-clean, proxy-valid candidates, 34 are non-worsening and 30 improve at signoff; proxy/final Spearman ρ=0.86 and Kendall τ=0.82. |
| Search/runtime/cost | WL/ECP/PWR generated 24/19/22 candidates, used 38/30/34 compile attempts, and promoted 5/4/5 signoff runs. Cold S0 is 4.6 h, incremental builds 6–18 min, proxy runs 35–90 min/design, and signoff 1.7–5.8 h/design. The audited LLM summary is 1,126 calls, 33.64M input tokens, 4.20M output tokens, and approximately US$77 under recorded pricing. |
| Formal scope | The selected WL/ECP/power modules contain 68/50/49 checked theorems with zero `sorry`; 71/100 candidates admitted a domain-specific obligation, while these three receive the full released Lean models: [`OpenRoadWlFull.lean`](formal/headline-contracts/OpenRoadWlFull.lean), [`OpenRoadEcpFull.lean`](formal/headline-contracts/OpenRoadEcpFull.lean), and [`OpenRoadPwrFull.lean`](formal/headline-contracts/OpenRoadPwrFull.lean). |

These are pinned evaluation results, not claims of universal dominance or
bit-identical regeneration of stochastic model outputs.
