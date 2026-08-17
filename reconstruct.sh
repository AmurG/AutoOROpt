#!/usr/bin/env bash
#
# reconstruct.sh
#
# Reconstruct the customized ORFS source tree under the output directory:
#
#   <DEST>/OpenROAD-flow-scripts/   (customized ORFS tree)
#
# The ORFS tree is assembled from:
#   - The-OpenROAD-Project/OpenROAD-flow-scripts @ 93c42b2e6  (main ORFS state)
#   - The-OpenROAD-Project/OpenROAD-flow-scripts @ 1edbcba12  (source of flow/scripts_ecp)
#   - The-OpenROAD-Project/OpenROAD            @ 7bc521f36a  (base for 4 OpenROAD variants)
#   - diffs/ecp/OpenROAD_ecp.patch
#   - diffs/pwr/OpenROAD_pwr.patch
#   - diffs/wl/OpenROAD_rwl.patch
#   - orfs_customizations.patch
#
# Usage:
#   ./reconstruct.sh [DEST]
#
#   DEST defaults to "." (the current working directory). It is treated as
#   the PARENT of the output. The script refuses to run if the output
#   already exists inside DEST.
#
# Build artifacts (build/, flow/logs, flow/objects, flow/reports, flow/results)
# are intentionally NOT reproduced, and neither are non-semantic 644 -> 755
# file-mode flips.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

DEST="${1:-.}"
mkdir -p "$DEST"
DEST="$(cd "$DEST" && pwd)"   # resolve to absolute

ORFS_DIR="$DEST/OpenROAD-flow-scripts"

# --- Pinned commits (do NOT update these; patches depend on exact SHAs) ---
ORFS_BASE=93c42b2e6877550589af655e0eb299038426e915
ORFS_SCRIPTS_COMMIT=1edbcba1243b91213f8dde2b89b623fe114300e6
OR_BASE=7bc521f36a34c986885473856e9f5b464093e38a

# --- Upstream URLs ---
ORFS_URL=https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts.git
OR_URL=https://github.com/The-OpenROAD-Project/OpenROAD.git

# --- Patch file locations ---
PATCH_ORFS="$SCRIPT_DIR/orfs_customizations.patch"
PATCH_ECP="$SCRIPT_DIR/diffs/ecp/OpenROAD_ecp.patch"
PATCH_PWR="$SCRIPT_DIR/diffs/pwr/OpenROAD_pwr.patch"
PATCH_RWL="$SCRIPT_DIR/diffs/wl/OpenROAD_rwl.patch"

log() { printf '[reconstruct] %s\n' "$*"; }

# --- Sanity checks on inputs ---
for f in "$PATCH_ORFS" "$PATCH_ECP" "$PATCH_PWR" "$PATCH_RWL"; do
  if [ ! -f "$f" ]; then
    echo "ERROR: required input not found: $f" >&2
    exit 1
  fi
done

# --- Sanity checks on outputs ---
if [ -e "$ORFS_DIR" ]; then
  echo "ERROR: output already exists: $ORFS_DIR" >&2
  echo "       remove it first or choose a different DEST" >&2
  exit 1
fi
log "DEST          = $DEST"
log "ORFS_DIR      = $ORFS_DIR"
log "ORFS base     = $ORFS_BASE"
log "ORFS scripts  = $ORFS_SCRIPTS_COMMIT"
log "OpenROAD base = $OR_BASE"
log "inputs dir    = $SCRIPT_DIR"

# --- 1. Clone ORFS at the main base commit ---
log "step 1/7: clone ORFS at $ORFS_BASE"
git clone "$ORFS_URL" "$ORFS_DIR"
cd "$ORFS_DIR"
git checkout "$ORFS_BASE"

# --- 2. Initialize only yosys and yosys-slang submodules ---
# Skip tools/OpenROAD (replaced by 4 custom variants below).
# Skip tools/kepler-formal (not accessible from the upstream mirror).
log "step 2/7: init tools/yosys + tools/yosys-slang submodules"
git submodule update --init --recursive tools/yosys tools/yosys-slang

# Remove any empty/gitlinked tools/OpenROAD placeholder left by clone.
rm -rf tools/OpenROAD

# --- 3. Rename flow/scripts -> flow/scripts_ref ---
log "step 3/7: rename flow/scripts -> flow/scripts_ref"
mv flow/scripts flow/scripts_ref

# --- 4. Fetch the alternate ORFS commit and extract its flow/scripts ---
log "step 4/7: fetch $ORFS_SCRIPTS_COMMIT and extract flow/scripts as flow/scripts_ecp"
git fetch origin "$ORFS_SCRIPTS_COMMIT"
TMP_ECP_EXTRACT="$ORFS_DIR/.tmp_ecp_extract"
rm -rf "$TMP_ECP_EXTRACT"
mkdir "$TMP_ECP_EXTRACT"
git archive "$ORFS_SCRIPTS_COMMIT" flow/scripts | tar -x -C "$TMP_ECP_EXTRACT"
mv "$TMP_ECP_EXTRACT/flow/scripts" flow/scripts_ecp
rm -rf "$TMP_ECP_EXTRACT"

# --- 5. Clone OpenROAD base once into tools/OpenROAD_ref, init submodules ---
log "step 5/7: clone OpenROAD at $OR_BASE into tools/OpenROAD_ref"
git clone "$OR_URL" tools/OpenROAD_ref
(
  cd tools/OpenROAD_ref
  git checkout "$OR_BASE"
  git submodule update --init --recursive
)

# --- 6. Copy ref to ecp/pwr/rwl and apply per-variant patches ---
log "step 6/7: copy OpenROAD_ref to _ecp/_pwr/_rwl and apply 3 patches"
cp -r tools/OpenROAD_ref tools/OpenROAD_ecp
cp -r tools/OpenROAD_ref tools/OpenROAD_pwr
cp -r tools/OpenROAD_ref tools/OpenROAD_rwl

( cd tools/OpenROAD_ecp && git apply "$PATCH_ECP" )
( cd tools/OpenROAD_pwr && git apply "$PATCH_PWR" )
( cd tools/OpenROAD_rwl && git apply "$PATCH_RWL" )

# --- 7. Apply ORFS customizations patch ---
# This contains:
#   - 22 tracked file modifications (flow/Makefile + 21 *.sdc)
#   - 136 new untracked files (117 config_for_*.mk, 12 new *.sdc, 2 *.sh,
#                              2 *.py, 1 *.v, 2 symlinks for scripts_pwr/rwl)
log "step 7/7: apply orfs_customizations.patch"
git apply "$PATCH_ORFS"

# --- Done ---
log ""
log "reconstruction complete"
log "  $ORFS_DIR"
log ""
log "NOTE: build artifacts (build*/, flow/logs, flow/objects, flow/reports,"
log "      flow/results) and 644->755 mode-bit flips are intentionally NOT"
log "      reproduced."
