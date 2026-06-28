#!/usr/bin/env bash
# Optimize a raw Meshy/other GLB for the PC (HD) build + Godot import.
#
#   tools/optimize_glb_pc.sh  input.glb  [output.glb]  [keep_ratio]
#
# This is the higher-quality sibling of optimize_glb.sh (which targets mobile).
# The PC build loads models from models/pc/, so by default we WRITE THERE:
#   * no output given  -> models/pc/<input-basename>.glb
#
# What it does, in order:
#   * resize textures down to 1024px max (Meshy ships 2K-4K; on a 4GB GPU a
#     2K x4-map model is ~90MB VRAM, which is what made the PC build stall).
#     PC keeps 1024 rather than mobile's tighter budget for crisper detail.
#   * weld vertices
#   * simplify ONLY if the file is still heavy: meshes are decimated to
#     keep_ratio of their vertices (default 0.18 ~= keep most detail). Light
#     models are left at full poly so HD geometry stays sharp.
# Like the mobile script it deliberately does NOT use Draco/meshopt: Godot
# 4.7's glTF importer can't decode KHR_draco_mesh_compression without a plugin.
#
# Tuning knobs (env vars):
#   TEX=1024        max texture dimension (set 2048 for max fidelity, more VRAM)
#   SIMPLIFY_MB=8   only simplify files larger than this many MB after resize
#   RATIO=0.5       vertices to keep when a file IS simplified
#   ERROR=0.003     max simplify error (raise to decimate harder, risk damage)
#
# NOTE: simplify can collapse THIN structures (petrol-station canopies, signs,
# railings). The defaults are deliberately gentle. For a hero asset that still
# looks wrong after this, run with RATIO=1 (skip simplify, texture resize only).
set -euo pipefail

IN="${1:?usage: optimize_glb_pc.sh input.glb [output.glb] [keep_ratio]}"

# Default output: models/pc/<basename> next to the repo's HD override folder.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PC_DIR="$(cd "$SCRIPT_DIR/.." && pwd)/models/pc"
OUT="${2:-$PC_DIR/$(basename "$IN")}"

TEX="${TEX:-1024}"
SIMPLIFY_MB="${SIMPLIFY_MB:-8}"
RATIO="${3:-${RATIO:-0.5}}"
ERROR="${ERROR:-0.003}"

GT="npx --yes @gltf-transform/cli@4"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$(dirname "$OUT")"

# 1) Texture resize — the single biggest VRAM win.
$GT resize "$IN" "$TMP/a.glb" --width "$TEX" --height "$TEX"
$GT weld   "$TMP/a.glb" "$TMP/b.glb"

# 2) Only decimate geometry when the model is still heavy after resizing, so
#    light HD models keep full detail.
SIZE_MB=$(du -m "$TMP/b.glb" | cut -f1)
if [ "$SIZE_MB" -gt "$SIMPLIFY_MB" ] && [ "$RATIO" != "1" ]; then
	echo "  ${SIZE_MB}MB > ${SIMPLIFY_MB}MB -> simplify --ratio $RATIO --error $ERROR"
	$GT simplify "$TMP/b.glb" "$OUT" --ratio "$RATIO" --error "$ERROR"
else
	echo "  ${SIZE_MB}MB <= ${SIMPLIFY_MB}MB -> keep full poly"
	cp "$TMP/b.glb" "$OUT"
fi

echo "optimized (PC) -> $OUT"
du -h "$OUT" | cut -f1
