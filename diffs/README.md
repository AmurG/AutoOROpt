# Headline OpenROAD diffs

This directory contains the three source-code patch families evaluated in the
ICCAD 2026 paper, “Automated QoR improvement in OpenROAD with coding agents.”

## Authoritative base snapshot

Apply all three patches to OpenROAD commit
`7bc521f36a34c986885473856e9f5b464093e38a`.  The surrounding evaluation tree
uses OpenROAD-flow-scripts commit
`93c42b2e6877550589af655e0eb299038426e915`; selected ECP flow scripts are
recovered from `1edbcba1243b91213f8dde2b89b623fe114300e6`.

These are the pins encoded in [`../reconstruct.sh`](../reconstruct.sh), the
authoritative way to assemble the evaluation source tree.

## Patch map

| Directory | OpenROAD area | Reported objective |
|---|---|---|
| `wl/` | DPL | Routed wirelength |
| `ecp/` | GPL and RSZ | Effective clock period |
| `pwr/` | RSZ | Total power |

Each directory contains a patch suitable for `git apply` at the pinned
OpenROAD base.  For a complete tree, including design configuration and flow
changes, run from the repository root:

```bash
./reconstruct.sh /path/to/output-parent
```

The resulting tree contains reference, routed-wirelength, ECP, and power
OpenROAD variants.  Replaying the paper’s QoR measurements additionally
requires the documented PDK/library inputs and the compute resources needed by
the corresponding ORFS runs.

## Interpretation

Patch applicability is not a QoR guarantee.  Rebasing to another OpenROAD
commit, changing a PDK or design, or changing flow settings requires new build,
proxy, and full-signoff evaluation.  Module cards used to ground the edits are
available under [`../docs/`](../docs/), and the scoped Lean contracts for the
three headline families are under
[`../formal/headline-contracts/`](../formal/headline-contracts/).
