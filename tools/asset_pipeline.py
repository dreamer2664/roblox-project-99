"""
asset_pipeline.py — CC0 source assets -> voxel box lists (.json) for the place builder.

Every entry is registered here with its licence so the generated repository always
carries a machine-readable provenance record (see CREDITS.md).
"""
import json, os, subprocess, sys, hashlib
from concurrent.futures import ProcessPoolExecutor

BLENDER = "/usr/local/bl/blender-4.5.15-linux-x64/blender"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DL = "/home/user/dl"
OUT = os.path.join(ROOT, "assets", "vox")

KITS = {
    "train": ("train-kit/Models/GLB format", "Kenney Train Kit", "CC0 1.0"),
    "com": ("city-kit-commercial/Models/GLB format", "Kenney City Kit (Commercial)", "CC0 1.0"),
    "sub": ("city-kit-suburban/Models/GLB format", "Kenney City Kit (Suburban)", "CC0 1.0"),
    "ind": ("city-kit-industrial/Models/GLB format", "Kenney City Kit (Industrial)", "CC0 1.0"),
    "roa": ("city-kit-roads/Models/GLB format", "Kenney City Kit (Roads)", "CC0 1.0"),
    "chr": ("mini-characters-1/Models/GLB format", "Kenney Mini Characters 1", "CC0 1.0"),
}

# name -> (kit, file, res, mode)
ASSETS = {
    # ---- rolling stock (Kenney Train Kit) ----
    "loco_city_a":      ("train", "train-electric-city-a.glb", 46, "surface"),
    "loco_city_b":      ("train", "train-electric-city-b.glb", 46, "surface"),
    "loco_bullet_a":    ("train", "train-electric-bullet-a.glb", 46, "surface"),
    "loco_double_a":    ("train", "train-electric-double-a.glb", 46, "surface"),
    "loco_passenger_a": ("train", "train-locomotive-passenger-a.glb", 46, "surface"),
    "loco_diesel_a":    ("train", "train-diesel-a.glb", 46, "surface"),
    "car_wood":         ("train", "train-carriage-wood.glb", 42, "surface"),
    "car_box":          ("train", "train-carriage-box.glb", 42, "surface"),
    "car_container":    ("train", "train-carriage-container-blue.glb", 40, "surface"),
    "tram_classic":     ("train", "train-tram-classic.glb", 44, "surface"),
    "tram_modern":      ("train", "train-tram-modern.glb", 44, "surface"),
    # ---- buildings ----
    "bld_sky_a":        ("com", "building-skyscraper-a.glb", 34, "surface"),
    "bld_sky_c":        ("com", "building-skyscraper-c.glb", 34, "surface"),
    "bld_sky_e":        ("com", "building-skyscraper-e.glb", 34, "surface"),
    "bld_com_a":        ("com", "building-a.glb", 34, "surface"),
    "bld_com_c":        ("com", "building-c.glb", 34, "surface"),
    "bld_com_f":        ("com", "building-f.glb", 34, "surface"),
    "bld_com_h":        ("com", "building-h.glb", 34, "surface"),
    "bld_com_k":        ("com", "building-k.glb", 34, "surface"),
    "bld_com_n":        ("com", "building-n.glb", 34, "surface"),
    "bld_sub_a":        ("sub", "building-type-a.glb", 32, "surface"),
    "bld_sub_d":        ("sub", "building-type-d.glb", 32, "surface"),
    "bld_sub_f":        ("sub", "building-type-f.glb", 32, "surface"),
    "bld_sub_j":        ("sub", "building-type-j.glb", 32, "surface"),
    "bld_sub_p":        ("sub", "building-type-p.glb", 32, "surface"),
    "bld_ind_b":        ("ind", "building-b.glb", 34, "surface"),
    "bld_ind_e":        ("ind", "building-e.glb", 34, "surface"),
    "bld_ind_h":        ("ind", "building-h.glb", 34, "surface"),
    "tower_water":      ("ind", "water-tower.glb", 32, "surface"),
    # ---- people (Kenney Mini Characters, CC0) ----
    "per_m_a":          ("chr", "character-male-a.glb", 40, "surface"),
    "per_m_c":          ("chr", "character-male-c.glb", 40, "surface"),
    "per_m_e":          ("chr", "character-male-e.glb", 40, "surface"),
    "per_m_g":          ("chr", "character-male-g.glb", 40, "surface"),
    "per_f_a":          ("chr", "character-female-a.glb", 40, "surface"),
    "per_f_c":          ("chr", "character-female-c.glb", 40, "surface"),
    "per_f_e":          ("chr", "character-female-e.glb", 40, "surface"),
    "per_worker":       ("chr", "character-worker.glb", 40, "surface"),
    "per_soldier":      ("chr", "character-soldier.glb", 40, "surface"),
    # ---- street furniture ----
    "prop_bench":       ("sub", "fence.glb", 30, "surface"),
    "prop_lamp":        ("roa", "light-curved.glb", 28, "surface"),
    "prop_lamp_sq":     ("roa", "light-square-double.glb", 28, "surface"),
    "prop_pole":        ("roa", "electricity-pole.glb", 26, "surface"),
    "prop_wires":       ("roa", "electricity-wires.glb", 26, "surface"),
    "prop_sign_hw":     ("roa", "sign-highway-detailed.glb", 26, "surface"),
    "prop_traffic":     ("roa", "traffic-light.glb", 26, "surface"),
    "prop_cone":        ("roa", "construction-cone.glb", 22, "surface"),
    "prop_barrier":     ("roa", "construction-barrier.glb", 24, "surface"),
    "prop_dumpster":    ("roa", "dumpster.glb", 24, "surface"),
    "prop_container":   ("ind", "shipping-container-a.glb", 28, "surface"),
    "prop_tank":        ("ind", "detail-tank.glb", 28, "surface"),
    "prop_planter":     ("sub", "planter.glb", 24, "surface"),
    "prop_tree_s":      ("sub", "tree-small.glb", 26, "surface"),
    "prop_tree_l":      ("sub", "tree-large.glb", 26, "surface"),
    "prop_awning":      ("com", "detail-awning-wide.glb", 24, "surface"),
    "prop_overhang":    ("com", "detail-overhang-wide.glb", 24, "surface"),
    "prop_tile":        ("roa", "tile-low.glb", 20, "surface"),
}


def job(item):
    name, (kit, fname, res, mode) = item
    kitdir, kitname, lic = KITS[kit]
    src = os.path.join(DL, kitdir, fname)
    dst = os.path.join(OUT, name + ".json")
    if not os.path.exists(src):
        return (name, "MISSING " + src)
    if os.path.exists(dst) and os.path.getsize(dst) > 64:
        return (name, "cached")
    cmd = [BLENDER, "-b", "-P", os.path.join(HERE, "voxelize.py"), "--",
           "--src", src, "--out", dst, "--res", str(res), "--mode", mode]
    r = subprocess.run(cmd, capture_output=True, text=True)
    ok = os.path.exists(dst)
    line = [l for l in r.stdout.splitlines() if l.startswith("VOX")]
    return (name, line[0] if line else ("FAIL " + r.stderr.strip()[-300:]))


def main():
    os.makedirs(OUT, exist_ok=True)
    only = sys.argv[1:] or list(ASSETS)
    items = [(n, ASSETS[n]) for n in only if n in ASSETS]
    with ProcessPoolExecutor(max_workers=2) as ex:
        for name, msg in ex.map(job, items):
            print(f"{name:16s} {msg}")
    # provenance record
    prov = {}
    for name, (kit, fname, res, mode) in ASSETS.items():
        p = os.path.join(OUT, name + ".json")
        if not os.path.exists(p):
            continue
        d = json.load(open(p))
        prov[name] = {
            "source_file": fname,
            "pack": KITS[kit][1],
            "license": KITS[kit][2],
            "tris_source": d["tris"],
            "parts": len(d["boxes"]),
            "wheel_groups": len(d.get("wheels", [])),
        }
    json.dump(prov, open(os.path.join(ROOT, "assets", "provenance.json"), "w"), indent=1)
    print("provenance entries:", len(prov))


if __name__ == "__main__":
    main()
