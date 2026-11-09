# Credits & asset licences

Every 3D model in this project comes from **open-source, CC0 (public domain) packs by
Kenney** (<https://kenney.nl>). CC0 means no attribution is legally required — this file
exists because credit is the decent thing to do, and because you should be able to audit
exactly where each asset came from.

Roblox cannot embed mesh data in a `.rbxl` file, so each source model is **voxelised at
build time** into axis-aligned parts (see `tools/voxelize.py`). The original `.glb` files
are kept verbatim in [`3d-models/`](3d-models/) next to the generated box lists in
[`assets/vox/`](assets/vox/), and every conversion is recorded in
[`assets/provenance.json`](assets/provenance.json) (source file, triangle count, part count).

| Pack | Author | Licence | Used for |
| --- | --- | --- | --- |
| Train Kit (1.1) | Kenney, with Guus Vermeulen & Tony Schaer | CC0 1.0 | All locomotives, coaches, wagons, rail/track pieces |
| City Kit — Commercial (2.1) | Kenney | CC0 1.0 | Skyscrapers, shopfronts, station-district buildings |
| City Kit — Suburban | Kenney | CC0 1.0 | Terrace housing, trees, planters, fences |
| City Kit — Industrial | Kenney | CC0 1.0 | Warehouses, water tower, tanks, containers |
| City Kit — Roads | Kenney | CC0 1.0 | Street lamps, traffic lights, poles, signs |
| Mini Characters 1 | Kenney | CC0 1.0 | Station crowds (9 variants) |

Licence texts are reproduced in `3d-models/LICENSES/`.

## Things that are mine (original work in this repo)

* `src/` — all Luau: alignment maths, station/architecture generators, catenary,
  viaduct, tunnel, city block placement, rolling-stock builder, train physics, cab UI.
* `tools/` — the voxeliser, asset pipeline, part dumper and Cycles renderer.
* All renders in `renders/` were produced from the built place file, not from mock-ups.

## Not included / caveats

* No Roblox marketplace assets, no uploaded MeshIds — the place is 100 % self-contained
  parts, so it opens without missing-asset warnings.
* Sound in-game uses engine-provided `rbxasset://` clips only (Roblox's own defaults).
