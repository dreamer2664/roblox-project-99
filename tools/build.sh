#!/usr/bin/env bash
# Full reproducible build:  CC0 sources -> voxel blueprints -> place file -> renders
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BLENDER=${BLENDER:-/usr/local/bl/blender-4.5.15-linux-x64/blender}
RBXMK=${RBXMK:-/home/user/tools/rbxmk}
cd "$ROOT"

echo "== 1/4  voxelise CC0 models"
python3 tools/asset_pipeline.py

echo "== 2/4  build the place"
"$RBXMK" run --desc-latest --allow-insecure-paths build.lua

echo "== 3/4  dump parts for offline rendering"
"$RBXMK" run --desc-latest --allow-insecure-paths tools/dump_parts.lua

echo "== 4/4  render stills"
"$BLENDER" -b -P tools/render_place.py -- --shots shots.json

echo "done -> out/RobloxProject99.rbxl, renders/"
