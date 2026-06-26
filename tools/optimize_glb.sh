#!/usr/bin/env bash
# Optimize a raw Meshy/other GLB for mobile + Godot import.
#
#   tools/optimize_glb.sh  input.glb  output.glb  [keep_ratio]
#
# Does, in order:
#   * resize all textures down to 1024px max  (Meshy ships 2K-4K = most of the MB)
#   * weld vertices
#   * simplify the mesh to ~keep_ratio of its vertices (default 0.06 ~= 30k tris
#     from a 500k Meshy mesh)
# It deliberately does NOT use Draco/meshopt compression: Godot 4.7's glTF
# importer can't decode KHR_draco_mesh_compression without a plugin.
set -euo pipefail

IN="${1:?usage: optimize_glb.sh input.glb output.glb [keep_ratio]}"
OUT="${2:?usage: optimize_glb.sh input.glb output.glb [keep_ratio]}"
RATIO="${3:-0.06}"

GT="npx --yes @gltf-transform/cli@4"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

$GT resize  "$IN"        "$TMP/a.glb" --width 1024 --height 1024
$GT weld    "$TMP/a.glb" "$TMP/b.glb"
$GT simplify "$TMP/b.glb" "$OUT" --ratio "$RATIO" --error 0.02

echo "optimized -> $OUT"
du -h "$OUT" | cut -f1
