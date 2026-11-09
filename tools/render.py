"""
render.py — offline Cycles renderer used for every screenshot/render in the repo.

Scenes are described in JSON so the same tool renders single-model turntables,
the assembled station, and the full rail corridor.

  blender -b -P render.py -- --spec shots/foo.json

Spec format:
{
  "out": "renders/foo.png", "w": 1600, "h": 900, "samples": 64,
  "world": "sunset" | "day" | "night" | "studio",
  "ground": {"color": [.2,.2,.2], "rough": 0.7, "size": 4000},
  "camera": {"az": 35, "el": 18, "focal": 50, "target": [0,4,0], "dist": 40},
  "objects": [
     {"src": "/path/model.glb", "height": 3.2, "pos": [0,0,0], "rot": [0,0,0],
      "shade": "smooth", "scale": 1.0}
  ],
  "instances": [ {"src":..., "height":..., "pos":..., "rot":...}, ... ]
}
"""
import bpy, sys, os, json, math, random
from mathutils import Vector, Euler

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SPEC = json.load(open(argv[argv.index("--spec") + 1]))


# ----------------------------------------------------------------------------- helpers
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 6
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 3
    sc.cycles.transmission_bounces = 4
    sc.cycles.sample_clamp_indirect = 4.0
    sc.cycles.use_adaptive_sampling = True
    sc.render.film_transparent = SPEC.get("transparent", False)
    sc.render.resolution_x = SPEC.get("w", 1600)
    sc.render.resolution_y = SPEC.get("h", 900)
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = SPEC["out"]
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Punchy" if SPEC.get("punchy", True) else "None"
    sc.cycles.samples = SPEC.get("samples", 64)
    sc.cycles.use_denoiser = True
    return sc


def import_model(src, height=None, pos=(0, 0, 0), rot=(0, 0, 0), scale=1.0, name=None):
    before = set(bpy.data.objects)
    ext = os.path.splitext(src)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj":
        bpy.ops.import_scene.obj(filepath=src)
    else:
        raise SystemExit("bad ext " + src)
    new = [o for o in bpy.data.objects if o not in before and o.type in ("MESH", "ARMATURE", "EMPTY")]
    new = [o for o in new if not any(k in o.name.lower() for k in ("icosphere", "shadow_plane"))]
    if not new:
        return None
    root = bpy.data.objects.new(name or os.path.basename(src).split(".")[0], None)
    bpy.context.collection.objects.link(root)
    for o in new:
        if o.parent is None:
            o.parent = root
    # normalise: sit on Z=0, centred in XY, optional uniform height
    bpy.context.view_layer.update()
    bb = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" for c in o.bound_box]
    if bb:
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        size = mx - mn
        if height and size.z > 1e-6:
            k = height / size.z
            root.scale = (k, k, k)
        else:
            root.scale = (scale, scale, scale)
        bpy.context.view_layer.update()
        bb = [o.matrix_world @ Vector(c) for o in new if o.type == "MESH" for c in o.bound_box]
        mn = Vector((min(v.x for v in bb), min(v.y for v in bb), min(v.z for v in bb)))
        mx = Vector((max(v.x for v in bb), max(v.y for v in bb), max(v.z for v in bb)))
        ctr = (mn + mx) / 2
        root.location = (pos[0] - ctr.x, pos[1] - ctr.y, pos[2] - mn.z)
        root.rotation_euler = Euler([math.radians(a) for a in rot], "XYZ")
    return root


def setup_world(kind):
    world = bpy.data.worlds.new("W")
    bpy.context.scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    if kind == "sunset":
        sky.sun_elevation = math.radians(7)
        sky.sun_rotation = math.radians(200)
        sky.air_density = 2.2
        sky.dust_density = 4.0
        bg.inputs["Strength"].default_value = 1.1
        bg.inputs["Color"].default_value = (1.0, 0.82, 0.66, 1)
    elif kind == "night":
        sky.sun_elevation = math.radians(-4)
        sky.air_density = 1.2
        bg.inputs["Strength"].default_value = 0.25
        bg.inputs["Color"].default_value = (0.16, 0.22, 0.42, 1)
    elif kind == "studio":
        sky.sky_type = "NISHITA"
        sky.sun_elevation = math.radians(30)
        bg.inputs["Strength"].default_value = 0.7
        bg.inputs["Color"].default_value = (0.55, 0.6, 0.7, 1)
    else:  # day
        sky.sun_elevation = math.radians(42)
        sky.sun_rotation = math.radians(150)
        sky.air_density = 1.4
        bg.inputs["Strength"].default_value = 1.0
        bg.inputs["Color"].default_value = (0.85, 0.9, 1.0, 1)
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])


def add_sun(kind):
    lamp = bpy.data.lights.new("Sun", "SUN")
    ob = bpy.data.objects.new("Sun", lamp)
    bpy.context.collection.objects.link(ob)
    if kind == "sunset":
        lamp.energy = 3.2
        lamp.color = (1.0, 0.72, 0.5)
        ob.rotation_euler = (math.radians(72), 0, math.radians(35))
    elif kind == "night":
        lamp.energy = 0.4
        lamp.color = (0.6, 0.7, 1.0)
        ob.rotation_euler = (math.radians(70), 0, math.radians(200))
    else:
        lamp.energy = 4.0
        lamp.color = (1.0, 0.96, 0.9)
        ob.rotation_euler = (math.radians(52), 0, math.radians(120))
    lamp.angle = math.radians(2.5)
    return ob


def add_ground(cfg):
    bpy.ops.mesh.primitive_plane_add(size=cfg.get("size", 6000), location=(0, 0, 0))
    g = bpy.context.object
    g.name = "Ground"
    mat = bpy.data.materials.new("GroundMat")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    c = cfg.get("color", [0.18, 0.18, 0.19])
    bsdf.inputs["Base Color"].default_value = (c[0], c[1], c[2], 1)
    bsdf.inputs["Roughness"].default_value = cfg.get("rough", 0.75)
    g.data.materials.append(mat)
    return g


def add_camera(cfg):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = cfg.get("focal", 50)
    cam.sensor_width = 36
    ob = bpy.data.objects.new("Cam", cam)
    bpy.context.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    tgt = Vector(cfg.get("target", [0, 0, 2]))
    dist = cfg.get("dist", 20)
    az = math.radians(cfg.get("az", 35))
    el = math.radians(cfg.get("el", 18))
    loc = tgt + Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el))) * dist
    ob.location = loc
    d = (tgt - loc).normalized()
    ob.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    if cfg.get("shift_z"):
        ob.location.z += cfg["shift_z"]
    return ob


def apply_shading(objs, mode):
    for o in objs:
        if o.type != "MESH":
            continue
        for p in o.data.polygons:
            p.use_smooth = (mode == "smooth")
        if mode == "smooth":
            o.data.use_auto_smooth = True if hasattr(o.data, "use_auto_smooth") else False


def main():
    sc = reset()
    wkind = SPEC.get("world", "day")
    setup_world(wkind)
    add_sun(wkind)
    if SPEC.get("ground"):
        add_ground(SPEC["ground"])
    # extra emissive point lights (street lamps at night)
    for L in SPEC.get("lights", []):
        lamp = bpy.data.lights.new(L.get("name", "L"), "POINT")
        lamp.energy = L.get("energy", 500)
        lamp.color = tuple(L.get("color", [1, 0.8, 0.5]))
        lamp.shadow_soft_size = L.get("radius", 0.6)
        ob = bpy.data.objects.new(L.get("name", "L"), lamp)
        ob.location = L["pos"]
        bpy.context.collection.objects.link(ob)

    objs = SPEC.get("objects", []) + SPEC.get("instances", [])
    for i, o in enumerate(objs):
        import_model(o["src"], height=o.get("height"), pos=o.get("pos", (0, 0, 0)),
                     rot=o.get("rot", (0, 0, 0)), scale=o.get("scale", 1.0),
                     name=o.get("name") or ("obj%d" % i))

    add_camera(SPEC.get("camera", {}))

    sc.cycles.samples = SPEC.get("samples", 64)
    sc.render.filepath = SPEC["out"]
    os.makedirs(os.path.dirname(SPEC["out"]), exist_ok=True)
    bpy.ops.render.render(write_still=True)
    print("RENDERED", SPEC["out"])


main()
