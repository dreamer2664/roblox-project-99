"""Inspect GLB files: bounding boxes, object names, materials. Run: blender -b -P inspect.py -- f1.glb f2.glb"""
import bpy, sys, os, json

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

def clean():
    bpy.ops.wm.read_factory_settings(use_empty=True)

def report(path):
    clean()
    bpy.ops.import_scene.gltf(filepath=path)
    objs = [o for o in bpy.data.objects]
    meshes = [o for o in objs if o.type == 'MESH']
    xs, ys, zs = [], [], []
    tris = 0
    for o in meshes:
        tris += len(o.data.loop_triangles) if o.data.loop_triangles else sum(len(p.vertices) - 2 for p in o.data.polygons)
        mw = o.matrix_world
        for c in o.bound_box:
            v = mw @ __import__("mathutils").Vector(c)
            xs.append(v.x); ys.append(v.y); zs.append(v.z)
    size = (max(xs) - min(xs), max(ys) - min(ys), max(zs) - min(zs)) if xs else (0, 0, 0)
    print("FILE", os.path.basename(path))
    print("  objects:", len(objs), "meshes:", len(meshes), "tris:", tris)
    print("  size XYZ: %.3f %.3f %.3f" % size)
    print("  min: %.3f %.3f %.3f  max: %.3f %.3f %.3f" % (min(xs), min(ys), min(zs), max(xs), max(ys), max(zs)))
    print("  names:", [o.name for o in objs][:12])
    print("  materials:", sorted({m.name for o in meshes for m in o.data.materials if m})[:8])
    print("  images:", [i.name for i in bpy.data.images][:8])

for p in argv:
    report(p)
