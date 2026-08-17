# AutoOROpt

Public collateral for **“Automated QoR improvement in OpenROAD with coding
agents”** (ICCAD 2026).  This repository is centered on the three reported
OpenROAD diffs, their reconstruction material, and the reported evaluation.
The numerical summary is collected in
[`EVALUATION_RESULTS.md`](EVALUATION_RESULTS.md), and the three checked Lean
models are under
[`formal/headline-contracts/`](formal/headline-contracts/).

For replay, treat [`reconstruct.sh`](reconstruct.sh) and
[`diffs/README.md`](diffs/README.md) as authoritative for repository pins.

## Repository structure

| Directory | Contents |
|-----------|----------|
| `diffs/wl/` | rWL improvement — DPL patch + modified source files (Table 2) |
| `diffs/ecp/` | ECP improvement — GPL+RSZ patch + modified source files (Table 4) |
| `diffs/pwr/` | Power improvement — RSZ patch (Table 5) |
| `docs/` | Auto-generated module documentation for DPL, GPL, RSZ (S0 output) |
| `plans/` | Example high-level and granular plans (S1/S2 output) |
| `formal/` | Timing-clamp gate and the three headline Lean models (S4) |
| `EVALUATION_RESULTS.md` | Baseline, audit, scope, runtime, and formal results |

The `reconstruct.sh` script below rebuilds the full ORFS source tree needed to run experiments.

## Step 1) Reconstruct the source tree

```bash
./reconstruct.sh [DEST]
```

`DEST` defaults to `.` (current directory). Produces:

```
<DEST>/OpenROAD-flow-scripts/   # reconstructed source tree
```

Prerequisites: `git`, `tar`, `cat`, `sha256sum`.

## Step 2) Build each tool

Build each of the 4 OpenROAD variants and yosys:

```bash
cd OpenROAD-flow-scripts/tools/OpenROAD_ref
mkdir -p build && cd build
cmake .. && make -j$(nproc)
```

Repeat for `OpenROAD_ecp`, `OpenROAD_pwr`, `OpenROAD_rwl`.
Build yosys under `tools/yosys` (`make -j$(nproc)`).

## Step 3) Run experiments

```bash
cd OpenROAD-flow-scripts/flow

# ECP improvement experiment
./batch_run.sh --for-ecp

# rWL improvement experiment
./batch_run.sh --for-rwl

# Power improvement experiment
./batch_run.sh --for-pwr
```

### Denoising experiment (noise sweep)

For denoising, run one target (`--for-ecp` or `--for-rwl`) across multiple clock-noise points, then aggregate.

```bash
# rWL denoising
./batch_run.sh --for-rwl -clock_noise -2,-1,0,1,2

# ECP denoising
./batch_run.sh --for-ecp -clock_noise -2,-1,0,1,2
```

## Step 4) Extract metrics and generate summary tables

Run these commands after the experiments finish:

```bash
cd OpenROAD-flow-scripts

# Parse design result directories and extract metrics into a Markdown table
python3 collect_metrics.py

# Generate denoised summary (best/median/worst over noise points)
python3 collect_metrics.py --denoise --denoised-output denoised_metrics.md

# Compare experiments using the generated Markdown metrics file
python3 compare_metrics.py -m "metrics_YYYYMMDD_HHMMSS.md"

# Compare denoised metrics
python3 compare_metrics.py -m "denoised_metrics.md" --all-summaries
```

### Denoised summary meaning

In `denoised_metrics.md`, runs from each noise sweep (-2/-1/0/1/2 ps) are
first ordered by one target metric for the same group.

- `for-ecp_noise`: ordered by `Eff_Clock` (smaller is better).
- `for-rwl_noise`: ordered by `Routed_WL` (smaller is better).

After ordering, the script picks:

- **Best**: first run
- **Median**: middle run
- **Worst**: last run

Then all Best/Median/Worst values (Count/Area/Power/Routed_WL/Eff_Clock/Slack)
are copied from those selected runs.

## Denoising Results

Each experiment was run five times with the clock period perturbed by −2 ps, −1 ps, 0 ps, +1 ps, and +2 ps relative to the nominal value. Runs are ordered by the target metric and summarized as **Best / Median / Worst**.

### TARGET = ECP

#### Best

| PDK | Design | TCP (ns) | Fail ref | Fail ecp | Cell ref | Cell ecp | Cell Δ% | Area ref | Area ecp | Area Δ% | Power ref | Power ecp | Power Δ% | rWL ref | rWL ecp | rWL Δ% | ECP ref | ECP ecp | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nangate45 | ariane133 (#macors=132) | 3.400 | 0 | 0 | 185081 | 184454 | -0.339% | 734438 | 733476 | -0.131% | 246.971 | 246.072 | -0.364% | 6798963 | 6351793 | -6.577% | 3.494 | 3.425 | -1.964% |
| nangate45 | ariane133 (#macros=133) | 3.400 | 0 | 0 | 190392 | 188802 | -0.835% | 743669 | 742370 | -0.175% | 253.718 | 251.902 | -0.716% | 7396687 | 7066996 | -4.457% | 3.474 | 3.443 | -0.917% |
| nangate45 | ariane136 () | 3 | 0 | 0 | 194948 | 194410 | -0.276% | 757366 | 757327 | -0.005% | 386.874 | 386.703 | -0.044% | 6770044 | 6981790 | 3.128% | 3.389 | 3.368 | -0.624% |
| nangate45 | ariane136 | 3 | 5 | 0 | - | 194410 | - | - | 757327 | - | - | 386.703 | - | - | 6981790 | - | - | 3.368 | - |
| nangate45 | bp_fe | 1.530 | 0 | 0 | 38817 | 38837 | 0.052% | 218833 | 219190 | 0.163% | 178.374 | 180.792 | 1.356% | 1534448 | 1489272 | -2.944% | 1.654 | 1.642 | -0.731% |
| nangate45 | swerv_wrapper | 1.700 | 0 | 0 | 107455 | 107243 | -0.197% | 644923 | 644427 | -0.077% | 293.862 | 293.386 | -0.162% | 3546615 | 3557555 | 0.308% | 2.129 | 2.131 | 0.098% |

#### Median

| PDK | Design | TCP (ns) | Fail ref | Fail ecp | Cell ref | Cell ecp | Cell Δ% | Area ref | Area ecp | Area Δ% | Power ref | Power ecp | Power Δ% | rWL ref | rWL ecp | rWL Δ% | ECP ref | ECP ecp | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nangate45 | ariane133 (#macors=132) | 3.400 | 0 | 0 | 185219 | 184837 | -0.206% | 734428 | 733764 | -0.090% | 248.227 | 247.115 | -0.448% | 6586206 | 6646525 | 0.916% | 3.591 | 3.426 | -4.598% |
| nangate45 | ariane133 (#macros=133) | 3.400 | 0 | 0 | 188948 | 189354 | 0.215% | 742480 | 743292 | 0.109% | 252.660 | 255.631 | 1.176% | 7506282 | 7216321 | -3.863% | 3.491 | 3.482 | -0.259% |
| nangate45 | ariane136 () | 3 | 0 | 0 | 195940 | 194736 | -0.614% | 758933 | 756904 | -0.267% | 396.468 | 386.708 | -2.462% | 7728347 | 7027115 | -9.074% | 3.730 | 3.399 | -8.874% |
| nangate45 | ariane136 | 3 | 5 | 0 | - | 194736 | - | - | 756904 | - | - | 386.708 | - | - | 7027115 | - | - | 3.399 | - |
| nangate45 | bp_fe | 1.530 | 0 | 0 | 37756 | 40161 | 6.370% | 218843 | 219955 | 0.508% | 181.448 | 180.387 | -0.585% | 1575347 | 1431210 | -9.150% | 1.669 | 1.674 | 0.260% |
| nangate45 | swerv_wrapper | 1.700 | 0 | 0 | 107401 | 107395 | -0.006% | 644617 | 644957 | 0.053% | 293.550 | 294.090 | 0.184% | 3523782 | 3555646 | 0.904% | 2.152 | 2.149 | -0.141% |

#### Worst

| PDK | Design | TCP (ns) | Fail ref | Fail ecp | Cell ref | Cell ecp | Cell Δ% | Area ref | Area ecp | Area Δ% | Power ref | Power ecp | Power Δ% | rWL ref | rWL ecp | rWL Δ% | ECP ref | ECP ecp | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nangate45 | ariane133 (#macors=132) | 3.400 | 0 | 0 | 184770 | 184973 | 0.110% | 733580 | 733695 | 0.016% | 247.066 | 245.663 | -0.568% | 6731905 | 6660872 | -1.055% | 3.670 | 3.471 | -5.415% |
| nangate45 | ariane133 (#macros=133) | 3.400 | 0 | 0 | 190196 | 190578 | 0.201% | 743519 | 744702 | 0.159% | 254.739 | 256.341 | 0.629% | 7197861 | 7644771 | 6.209% | 3.623 | 3.611 | -0.326% |
| nangate45 | ariane136 () | 3 | 0 | 0 | 195616 | 194683 | -0.477% | 758396 | 757187 | -0.159% | 396.083 | 387.196 | -2.244% | 7668442 | 7036804 | -8.237% | 3.785 | 3.407 | -10.002% |
| nangate45 | ariane136 | 3 | 5 | 0 | - | 194683 | - | - | 757187 | - | - | 387.196 | - | - | 7036804 | - | - | 3.407 | - |
| nangate45 | bp_fe | 1.530 | 0 | 0 | 40474 | 38690 | -4.408% | 220189 | 218634 | -0.706% | 181.502 | 180.420 | -0.596% | 1513338 | 1488021 | -1.673% | 1.716 | 1.677 | -2.248% |
| nangate45 | swerv_wrapper | 1.700 | 0 | 0 | 107509 | 107494 | -0.014% | 644846 | 645439 | 0.092% | 293.411 | 293.523 | 0.038% | 3534802 | 3567037 | 0.912% | 2.190 | 2.160 | -1.381% |

### TARGET = rWL

#### Best

| PDK | Design | TCP (ns) | Fail ref | Fail rwl | Cell ref | Cell rwl | Cell Δ% | Area ref | Area rwl | Area Δ% | Power ref | Power rwl | Power Δ% | rWL ref | rWL rwl | rWL Δ% | ECP ref | ECP rwl | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| asap7 | aes | 0.380 | 0 | 0 | 17817 | 17789 | -0.157% | 1920.240 | 1920.590 | 0.018% | 154.108 | 153.494 | -0.398% | 64254 | 62615 | -2.551% | 0.407 | 0.415 | 1.822% |
| asap7 | ibex | 1 | 0 | 0 | 21016 | 21018 | 0.010% | 2479.650 | 2480.280 | 0.025% | 54.651 | 54.975 | 0.594% | 79849 | 79490 | -0.450% | 1.123 | 1.113 | -0.908% |
| asap7 | jpeg | 0.680 | 0 | 0 | 58051 | 58043 | -0.014% | 6464.930 | 6464.170 | -0.012% | 119.982 | 119.565 | -0.348% | 154138 | 152232 | -1.237% | 0.666 | 0.662 | -0.643% |
| nangate45 | aes | 0.820 | 0 | 0 | 16185 | 16246 | 0.377% | 21648.400 | 21705.300 | 0.263% | 368.676 | 367.112 | -0.424% | 225936 | 217348 | -3.801% | 0.880 | 0.880 | 0.000% |
| nangate45 | ariane133 (#macros=132) | 4 | 1 | 0 | 186206 | 186308 | 0.055% | 735633 | 735754 | 0.016% | 217.991 | 217.794 | -0.090% | 7460920 | 7331364 | -1.736% | 4.128 | 4.220 | 2.219% |
| nangate45 | ariane133 (#macros=133) | 4 | 0 | 0 | 191168 | 191348 | 0.094% | 745162 | 745300 | 0.019% | 222.411 | 222.064 | -0.156% | 8014474 | 7874099 | -1.752% | 4.069 | 4.086 | 0.415% |
| nangate45 | ariane136 | 6 | 2 | 0 | 192962 | 192996 | 0.018% | 754721 | 754674 | -0.006% | 205.806 | 205.329 | -0.232% | 7934279 | 7499312 | -5.482% | 5.785 | 6.209 | 7.339% |
| nangate45 | bp_fe | 1.800 | 0 | 0 | 40024 | 39968 | -0.140% | 218975 | 218970 | -0.002% | 155.391 | 155.458 | 0.043% | 1600384 | 1632588 | 2.012% | 1.893 | 1.892 | -0.044% |
| nangate45 | ibex | 2.200 | 0 | 0 | 16185 | 16195 | 0.062% | 29076.200 | 29092.700 | 0.057% | 96.737 | 97.396 | 0.681% | 246335 | 245789 | -0.222% | 2.220 | 2.242 | 0.992% |
| nangate45 | jpeg | 1 | 0 | 0 | 65395 | 65404 | 0.014% | 94343.300 | 94337.400 | -0.006% | 500.077 | 498.412 | -0.333% | 558050 | 548501 | -1.711% | 1.120 | 1.120 | 0.000% |
| nangate45 | swerv_wrapper | 2 | 0 | 0 | 106353 | 106317 | -0.034% | 644544 | 644432 | -0.017% | 261.749 | 261.499 | -0.096% | 4309652 | 4237478 | -1.675% | 2.142 | 2.178 | 1.668% |
| sky130hd | aes | 4.500 | 0 | 0 | 18183 | 18308 | 0.687% | 114938 | 116957 | 1.757% | 408.205 | 413.632 | 1.329% | 659778 | 632140 | -4.189% | 4.510 | 4.430 | -1.774% |
| sky130hd | ibex | 10 | 0 | 0 | 19540 | 19502 | -0.194% | 161019 | 161143 | 0.077% | 93.312 | 93.481 | 0.181% | 643178 | 638684 | -0.699% | 10.590 | 10.434 | -1.469% |
| sky130hd | jpeg | 5.500 | 2 | 0 | 50558 | 50671 | 0.224% | 458945 | 460331 | 0.302% | 473.242 | 474.324 | 0.229% | 1207556 | 1188850 | -1.549% | 5.430 | 5.510 | 1.473% |

#### Median

| PDK | Design | TCP (ns) | Fail ref | Fail rwl | Cell ref | Cell rwl | Cell Δ% | Area ref | Area rwl | Area Δ% | Power ref | Power rwl | Power Δ% | rWL ref | rWL rwl | rWL Δ% | ECP ref | ECP rwl | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| asap7 | aes | 0.380 | 0 | 0 | 17864 | 17874 | 0.056% | 1924.720 | 1925.220 | 0.026% | 154.179 | 153.549 | -0.409% | 64640 | 62710 | -2.986% | 0.407 | 0.407 | 0.005% |
| asap7 | ibex | 1 | 0 | 0 | 21075 | 21092 | 0.081% | 2485.340 | 2492.130 | 0.273% | 55.888 | 55.322 | -1.012% | 80402 | 79784 | -0.769% | 1.116 | 1.111 | -0.420% |
| asap7 | jpeg | 0.680 | 0 | 0 | 58051 | 58063 | 0.021% | 6464.930 | 6469.660 | 0.073% | 119.981 | 120.010 | 0.024% | 154138 | 152266 | -1.214% | 0.666 | 0.665 | -0.114% |
| nangate45 | aes | 0.820 | 0 | 0 | 16292 | 16187 | -0.644% | 21759.900 | 21656.700 | -0.474% | 372.457 | 366.447 | -1.614% | 230044 | 217630 | -5.396% | 0.880 | 0.870 | -1.136% |
| nangate45 | ariane133 (#macros=132) | 4 | 1 | 0 | 186327 | 186328 | 0.001% | 735920 | 735878 | -0.006% | 218.485 | 218.188 | -0.136% | 7698293 | 7467814 | -2.994% | 4.138 | 4.117 | -0.508% |
| nangate45 | ariane133 (#macros=133) | 4 | 0 | 0 | 191341 | 191354 | 0.007% | 745270 | 745322 | 0.007% | 222.301 | 221.950 | -0.158% | 8175194 | 8005794 | -2.072% | 4.047 | 4.066 | 0.474% |
| nangate45 | ariane136 | 6 | 2 | 0 | 193046 | 193063 | 0.009% | 754735 | 754714 | -0.003% | 205.850 | 205.501 | -0.170% | 7986048 | 7509944 | -5.962% | 5.666 | 5.929 | 4.624% |
| nangate45 | bp_fe | 1.800 | 0 | 0 | 39752 | 39945 | 0.486% | 218752 | 219154 | 0.184% | 155.063 | 155.702 | 0.412% | 1602413 | 1634925 | 2.029% | 1.900 | 1.869 | -1.669% |
| nangate45 | ibex | 2.200 | 0 | 0 | 16122 | 16100 | -0.136% | 29023.500 | 29042.400 | 0.065% | 95.794 | 96.445 | 0.680% | 248490 | 247912 | -0.233% | 2.224 | 2.256 | 1.453% |
| nangate45 | jpeg | 1 | 0 | 0 | 65440 | 65463 | 0.035% | 94761.200 | 94600 | -0.170% | 505.821 | 503.648 | -0.430% | 565228 | 552252 | -2.296% | 1.120 | 1.110 | -0.893% |
| nangate45 | swerv_wrapper | 2 | 0 | 0 | 106491 | 106340 | -0.142% | 644957 | 644674 | -0.044% | 262.061 | 261.789 | -0.104% | 4322161 | 4242719 | -1.838% | 2.140 | 2.166 | 1.213% |
| sky130hd | aes | 4.500 | 0 | 0 | 18219 | 18314 | 0.521% | 115401 | 116407 | 0.872% | 412.626 | 409.842 | -0.675% | 661966 | 635833 | -3.948% | 4.600 | 4.730 | 2.826% |
| sky130hd | ibex | 10 | 0 | 0 | 19677 | 19663 | -0.071% | 162048 | 162312 | 0.163% | 97.836 | 97.409 | -0.437% | 646855 | 643006 | -0.595% | 10.702 | 10.806 | 0.964% |
| sky130hd | jpeg | 5.500 | 2 | 0 | 50566 | 50663 | 0.192% | 458905 | 460105 | 0.261% | 475.731 | 474.207 | -0.320% | 1217995 | 1204181 | -1.134% | 5.470 | 5.410 | -1.097% |

#### Worst

| PDK | Design | TCP (ns) | Fail ref | Fail rwl | Cell ref | Cell rwl | Cell Δ% | Area ref | Area rwl | Area Δ% | Power ref | Power rwl | Power Δ% | rWL ref | rWL rwl | rWL Δ% | ECP ref | ECP rwl | ECP Δ% |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| asap7 | aes | 0.380 | 0 | 0 | 17902 | 17830 | -0.402% | 1927.970 | 1925.220 | -0.143% | 154.523 | 154.233 | -0.188% | 65302 | 63537 | -2.703% | 0.414 | 0.411 | -0.876% |
| asap7 | ibex | 1 | 0 | 0 | 21107 | 21181 | 0.351% | 2496.260 | 2503.490 | 0.290% | 56.075 | 56.490 | 0.741% | 80470 | 80823 | 0.439% | 1.105 | 1.124 | 1.732% |
| asap7 | jpeg | 0.680 | 0 | 0 | 58039 | 58100 | 0.105% | 6467.030 | 6470.330 | 0.051% | 120.061 | 120.014 | -0.039% | 154484 | 152366 | -1.371% | 0.667 | 0.656 | -1.619% |
| nangate45 | aes | 0.820 | 0 | 0 | 16412 | 16361 | -0.311% | 21891 | 21829.600 | -0.280% | 376.865 | 369.835 | -1.865% | 238083 | 220425 | -7.417% | 0.930 | 0.880 | -5.376% |
| nangate45 | ariane133 (#macros=132) | 4 | 1 | 0 | 186447 | 186419 | -0.015% | 736037 | 736013 | -0.003% | 218.885 | 218.079 | -0.368% | 7831361 | 7523708 | -3.928% | 4.143 | 4.159 | 0.371% |
| nangate45 | ariane133 (#macros=133) | 4 | 0 | 0 | 191724 | 191766 | 0.022% | 745657 | 745730 | 0.010% | 222.697 | 222.314 | -0.172% | 8329081 | 8127050 | -2.426% | 4.065 | 4.105 | 0.995% |
| nangate45 | ariane136 | 6 | 2 | 0 | 193131 | 192875 | -0.133% | 754888 | 754590 | -0.039% | 206.165 | 205.363 | -0.389% | 7991128 | 7521068 | -5.882% | 5.665 | 6.018 | 6.226% |
| nangate45 | bp_fe | 1.800 | 0 | 0 | 40080 | 39829 | -0.626% | 219016 | 218797 | -0.100% | 155.331 | 155.103 | -0.147% | 1603884 | 1636090 | 2.008% | 1.907 | 1.915 | 0.418% |
| nangate45 | ibex | 2.200 | 0 | 0 | 16073 | 16122 | 0.305% | 29000.100 | 29023 | 0.079% | 95.980 | 95.796 | -0.192% | 249386 | 248545 | -0.337% | 2.236 | 2.247 | 0.452% |
| nangate45 | jpeg | 1 | 0 | 0 | 65474 | 65482 | 0.012% | 94662.800 | 94612.500 | -0.053% | 505.957 | 502.678 | -0.648% | 568880 | 554902 | -2.457% | 1.190 | 1.110 | -6.723% |
| nangate45 | swerv_wrapper | 2 | 0 | 0 | 106570 | 106548 | -0.021% | 644473 | 644855 | 0.059% | 261.250 | 261.095 | -0.059% | 4343557 | 4269220 | -1.711% | 2.247 | 2.184 | -2.793% |
| sky130hd | aes | 4.500 | 0 | 0 | 18342 | 18361 | 0.104% | 116126 | 117085 | 0.826% | 415.933 | 414.068 | -0.448% | 673218 | 642849 | -4.511% | 4.480 | 5.380 | 20.089% |
| sky130hd | ibex | 10 | 0 | 0 | 19602 | 19585 | -0.087% | 161600 | 161100 | -0.309% | 96.746 | 96.112 | -0.656% | 655605 | 653544 | -0.314% | 10.657 | 10.752 | 0.895% |
| sky130hd | jpeg | 5.500 | 2 | 0 | 50730 | 50733 | 0.006% | 461559 | 460926 | -0.137% | 481.276 | 481.562 | 0.059% | 1243782 | 1222622 | -1.701% | 5.500 | 5.460 | -0.727% |

## What the scripts do

**Location:** `OpenROAD-flow-scripts/flow/`

#### `batch_run.sh` — Batch orchestrator
Runs many design/PDK/noise/selector combinations in parallel using a simple queue-based scheduler.

#### `run.sh` — Single-run executor
Executes the full flow (synthesis -> place -> route -> reports) for a single design run.

---

**Location:** `OpenROAD-flow-scripts/`

#### `collect_metrics.py` — Metrics collector
Scans OpenROAD run directories and extracts key metrics from report JSONs, routing JSONs, SDCs, and logs (area, power, slack, clocks, routed wirelength, etc.).
Writes:
- `metrics_YYYYMMDD_HHMMSS.md`
- `denoised_metrics.md` (when `--denoise` is used)

#### `compare_metrics.py` — Metrics comparator (Excel)
Reads a `metrics_*.md` file or `denoised_metrics.md` and generates Excel comparisons across variants (e.g., `ref` vs `ecp` / `rwl` / `pwr`).
Outputs:
- `metrics_comparisons.xlsx`
