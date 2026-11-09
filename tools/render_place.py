"""
render_place.py — render the ACTUAL generated place with Cycles.

Reads out/parts.json (every BasePart of the built .rbxl: position, rotation basis,
size, colour, material class) and rebuilds it as bmesh boxes in Blender, then renders
cinematic shots. Because the geometry comes straight out of the place file, these
images are honest previews of what Studio will open.

  blender -b -P tools/render_place.py -- shots/pack.json

Shot spec:
{ "shots": [ { "name": "01_terminus", "pos": [x,y,z], "target": [x,y,z], "focal": 35,
               "world": "sunset", "samples": 64, "w": 1920, "h": 1080,
               "clip_end": 4000 } ] }
"""
import bpy, bmesh, json, math, os, sys, time
from mathutils import Vector, Matrix

ROOT = "/home/user/rblx99"
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
SPEC = json.load(open(argv[argv.index("--shots") + 1]))
OUTDIR = SPEC.get("outdir", os.path.join(ROOT, "renders"))


# --------------------------------------------------------------------------- scene
def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 48
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.render.use_persistent_data = False
    sc.cycles.max_bounces = 4
    sc.cycles.diffuse_bounces = 3
    sc.cycles.glossy_bounces = 2
    sc.cycles.transmission_bounces = 3
    sc.cycles.transparent_max_bounces = 4
    sc.cycles.use_adaptive_sampling = True
    sc.cycles.adaptive_threshold = 0.02
    sc.cycles.sample_clamp_indirect = 3.0
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_depth = "8"
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Punchy"
    return sc


MATS = {}


def material(kind, rgb):
    """kind: 0 plastic, 1 neon, 2 glass"""
    key = (kind,)
    if key in MATS:
        return MATS[key]
    m = bpy.data.materials.new("m%d" % kind)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    col = tuple(min(1.0, c) ** 2.2 for c in rgb) + (1.0,)
    bsdf.inputs["Base Color"].default_value = col
    if kind == 1:      # neon / lamps
        bsdf.inputs["Emission Color"].default_value = col
        bsdf.inputs["Emission Strength"].default_value = 4.0
        bsdf.inputs["Roughness"].default_value = 0.4
    elif kind == 2:    # glass
        bsdf.inputs["Roughness"].default_value = 0.05
        bsdf.inputs["Metallic"].default_value = 0.0
        try:
            bsdf.inputs["Transmission Weight"].default_value = 0.75
        except KeyError:
            pass
        bsdf.inputs["Alpha"].default_value = 0.35
        m.blend_method = "BLEND"
    elif kind == 3:    # water
        bsdf.inputs["Roughness"].default_value = 0.04
        bsdf.inputs["Metallic"].default_value = 0.1
    else:
        bsdf.inputs["Roughness"].default_value = 0.82
    MATS[key] = m
    return m


def build_parts(parts, box_scale=1.0):
    """Rebuild every BasePart as a box in one mesh, preserving per-face colour."""
    bm = bmesh.new()
    metas = []          # (kind, (r,g,b)) per face, in creation order
    made = 0
    for p in parts:
        x, y, z, rx, ry, rz, ux, uy, uz, lx, ly, lz, sx, sy, sz, cr, cg, cb, kind = p
        sx *= box_scale
        sy *= box_scale
        sz *= box_scale
        if sx * sy * sz < 2e-4 or sx < 0.02 or sy < 0.02 or sz < 0.02:
            continue
        R = Matrix((Vector((rx, ry, rz)), Vector((ux, uy, uz)), Vector((lx, ly, lz)))).transposed()
        centre = Vector((x, y, z))
        vs = []
        for ix in (-0.5, 0.5):
            for iy in (-0.5, 0.5):
                for iz in (-0.5, 0.5):
                    vs.append(bm.verts.new(centre + R @ Vector((ix * sx, iy * sy, iz * sz))))
        for f in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1),
                  (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            bm.faces.new([vs[i] for i in f])
            metas.append((min(kind, 2), (cr, cg, cb)))
        made += 1

    me = bpy.data.meshes.new("place")
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new("Place", me)
    bpy.context.collection.objects.link(ob)

    for k in range(3):
        me.materials.append(material(k, (0.75, 0.75, 0.75)))
    me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    col_layer = me.color_attributes["Col"]

    polys = me.polygons
    n = min(len(polys), len(metas))
    for i in range(n):
        slot, col = metas[i]
        poly = polys[i]
        poly.material_index = slot
        for li in poly.loop_indices:
            col_layer.data[li].color = (col[0], col[1], col[2], 1.0)

    # base colour = vertex colour (sRGB->linear handled roughly by the power curve upstream)
    for k in range(3):
        mat = me.materials[k]
        nt = mat.node_tree
        bsdf = nt.nodes["Principled BSDF"]
        attr = nt.nodes.new("ShaderNodeVertexColor")
        attr.layer_name = "Col"
        nt.links.new(attr.outputs["Color"], bsdf.inputs["Base Color"])
        if k == 1:
            try:
                nt.links.new(attr.outputs["Color"], bsdf.inputs["Emission Color"])
            except KeyError:
                pass
    print("PARTS_IN_MESH", made, "faces", n)
    return ob


# --------------------------------------------------------------------------- world
def setup_world(kind):
    w = bpy.data.worlds.new("W")
    bpy.context.scene.world = w
    w.use_nodes = True
    nt = w.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputWorld")
    bg = nt.nodes.new("ShaderNodeBackground")
    sky = nt.nodes.new("ShaderNodeTexSky")
    sky.sky_type = "NISHITA"
    if kind == "sunset":
        sky.sun_elevation = math.radians(6)
        sky.sun_rotation = math.radians(200)
        sky.air_density = 2.4
        sky.dust_density = 4.5
        bg.inputs["Strength"].default_value = 1.2
    elif kind == "golden":
        sky.sun_elevation = math.radians(13)
        sky.sun_rotation = math.radians(160)
        sky.air_density = 1.8
        sky.dust_density = 2.6
        bg.inputs["Strength"].default_value = 1.0
    elif kind == "night":
        sky.sun_elevation = math.radians(-6)
        bg.inputs["Strength"].default_value = 0.5
    elif kind == "overcast":
        sky.sun_elevation = math.radians(35)
        sky.air_density = 3.2
        sky.dust_density = 6.0
        bg.inputs["Strength"].default_value = 1.1
    else:
        sky.sun_elevation = math.radians(40)
        sky.sun_rotation = math.radians(140)
        sky.air_density = 1.5
        bg.inputs["Strength"].default_value = 1.0
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    nt.links.new(bg.outputs["Background"], out.inputs["Surface"])

    lamp = bpy.data.lights.new("Sun", "SUN")
    ob = bpy.data.objects.new("Sun", lamp)
    bpy.context.collection.objects.link(ob)
    if kind == "sunset":
        lamp.energy = 3.6
        lamp.color = (1.0, 0.68, 0.46)
        ob.rotation_euler = (math.radians(80), 0, math.radians(40))
    elif kind == "night":
        lamp.energy = 0.25
        lamp.color = (0.55, 0.65, 1.0)
        ob.rotation_euler = (math.radians(70), 0, math.radians(220))
    elif kind == "overcast":
        lamp.energy = 1.6
        lamp.color = (0.92, 0.95, 1.0)
        ob.rotation_euler = (math.radians(55), 0, math.radians(120))
    else:
        lamp.energy = 3.4
        lamp.color = (1.0, 0.95, 0.88)
        ob.rotation_euler = (math.radians(55), 0, math.radians(135))
    lamp.angle = math.radians(3.0)


def add_camera(shot):
    cam = bpy.data.cameras.new("Cam")
    cam.lens = shot.get("focal", 35)
    cam.sensor_width = 36
    cam.clip_start = 0.1
    cam.clip_end = shot.get("clip_end", 5000)
    ob = bpy.data.objects.new("Cam", cam)
    bpy.context.collection.objects.link(ob)
    bpy.context.scene.camera = ob
    pos = Vector(shot["pos"])
    tgt = Vector(shot["target"])
    if shot.get("ortho"):
        cam.type = "ORTHO"
        cam.ortho_scale = shot["ortho"]
    ob.location = pos
    ob.rotation_euler = (tgt - pos).to_track_quat("-Z", "Y").to_euler()
    if shot.get("dof"):
        cam.dof.use_dof = True
        cam.dof.focus_distance = (tgt - pos).length
        cam.dof.aperture_fstop = shot["dof"]
    return ob


def add_fills(shot):
    for L in shot.get("lights", []):
        lamp = bpy.data.lights.new("Fill", L.get("type", "AREA"))
        lamp.energy = L.get("energy", 3000)
        lamp.color = tuple(L.get("color", (1.0, 0.92, 0.8)))
        if L.get("type", "AREA") == "AREA":
            lamp.shape = "RECTANGLE"
            lamp.size = L.get("size", 12)
            lamp.size_y = L.get("size_y", 12)
        ob = bpy.data.objects.new("Fill", lamp)
        ob.location = Vector(L["pos"])
        if L.get("target"):
            ob.rotation_euler = (Vector(L["target"]) - Vector(L["pos"])).to_track_quat("-Z", "Y").to_euler()
        bpy.context.collection.objects.link(ob)


def main():
    t0 = time.time()
    parts = json.load(open(os.path.join(ROOT, "out", "parts.json")))
    print("LOADED", len(parts), "parts in %.1fs" % (time.time() - t0))
    os.makedirs(OUTDIR, exist_ok=True)
    sc = reset()
    ob = build_parts(parts)
    print("MESH BUILT %.1fs" % (time.time() - t0))
    # bounding info for logging
    for shot in SPEC["shots"]:
        # clear previous fill lights
        for ob in list(bpy.data.objects):
            if ob.type == "LIGHT" and ob.name.startswith("Fill"):
                bpy.data.objects.remove(ob, do_unlink=True)
        sc.view_settings.exposure = shot.get("exposure", 0.0)
        sc.render.resolution_x = shot.get("w", 1920)
        sc.render.resolution_y = shot.get("h", 1080)
        sc.cycles.samples = shot.get("samples", 48)
        # rebuild world per shot (cheap)
        setup_world(shot.get("world", "day"))
        add_camera(shot)
        add_fills(shot)
        path = os.path.join(OUTDIR, shot["name"] + ".png")
        if os.path.exists(path) and os.path.getsize(path) > 10000 and not SPEC.get("force"):
            print("SKIP", shot["name"])
            continue
        sc.render.filepath = path
        t1 = time.time()
        bpy.ops.render.render(write_still=True)
        print("SHOT %s %.1fs" % (shot["name"], time.time() - t1))


main()
