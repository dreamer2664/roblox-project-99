"""
voxelize.py — convert CC0 glTF/GLB models into native Roblox parts.

Roblox .rbxl files cannot contain mesh geometry, so every imported open-source
model is voxelized (surface or solid) and greedy-meshed into axis-aligned boxes.
Each box becomes a Part in the generated place -- no cloud asset IDs required.

Usage (inside Blender):
  blender -b -P voxelize.py -- --src model.glb --out model.vox.json \
      --res 48 --mode surface [--height 6.0]
"""
import bpy, sys, os, json, math
from mathutils import Vector
import numpy as np

argv = sys.argv[sys.argv.index("--") + 1:]


def arg(name, default=None):
    if name in argv:
        return argv[argv.index(name) + 1]
    return default


SRC = arg("--src")
OUT = arg("--out")
RES = int(arg("--res", "40"))
MODE = arg("--mode", "surface")
HEIGHT = float(arg("--height", "0"))
MIN_SHARE = float(arg("--minshare", "0.0006"))


def load(path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(path)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=path)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=path)
    elif ext == ".obj":
        bpy.ops.import_scene.obj(filepath=path)
    else:
        raise SystemExit("unsupported " + ext)
    skip = ("icosphere", "shadow", "plane")
    return [o for o in bpy.data.objects
            if o.type == "MESH" and not any(k in o.name.lower() for k in skip)]


def mesh_data(objs):
    """Return (verts Nx3 world, tris Mx3 index, tri_owner M, colours Nx3, groups)."""
    V, T, TM, C = [], [], [], []
    off = 0
    groups = []          # (name, kind, vert_start, vert_end)
    for ob in objs:
        gstart = off
        gkind = "wheel" if "wheel" in ob.name.lower() else "body"
        me = ob.data
        me.calc_loop_triangles()
        mw = ob.matrix_world
        vs = [mw @ v.co for v in me.vertices]
        V.extend([(v.x, v.y, v.z) for v in vs])
        for tri in me.loop_triangles:
            T.append(tuple(i + off for i in tri.vertices))
            mi = 0
            if me.materials and tri.material_index < len(me.materials):
                pass
            TM.append(mi)
        # per-vertex colour from the first colour attribute if present
        cols = np.ones((len(me.vertices), 3), dtype=float)
        if me.color_attributes:
            ca = me.color_attributes[0]
            try:
                for i, d in enumerate(ca.data):
                    if i < len(cols):
                        cols[i] = (d.color[0], d.color[1], d.color[2])
            except Exception:
                pass
        C.extend(cols.tolist())
        off += len(me.vertices)
        groups.append({"name": ob.name, "kind": gkind, "v0": gstart, "v1": off})
    return (np.array(V, dtype=float), np.array(T, dtype=np.int64),
            np.array(TM, dtype=np.int64), np.array(C, dtype=float), groups)


def sample_colours(V, T, C=None, img_colours=None, fallback=(0.72, 0.74, 0.78)):
    """Average colour per triangle -> per voxel. Uses material base colour texture
    sampled at the triangle's barycentric centroid if available."""
    n = len(T)
    out = np.tile(np.array(fallback, dtype=float), (n, 1))
    if img_colours is not None:
        tex, w, h = img_colours
        cent = V[T].mean(axis=1)
        # planar UV fallback: use world XZ mapped into [0,1] -- approximate but keeps palette
        mn = cent.min(axis=0); mx = cent.max(axis=0)
        span = np.maximum(mx - mn, 1e-6)
        u = ((cent[:, 0] - mn[0]) / span[0] * (w - 1)).astype(int)
        v = ((cent[:, 2] - mn[2]) / span[2] * (h - 1)).astype(int)
        u = np.clip(u, 0, w - 1); v = np.clip(v, 0, h - 1)
        out = tex[v, u]
    return out


def get_texture():
    """Pull the 'colormap' image straight from the GLB buffer."""
    for img in bpy.data.images:
        if img.size[0] < 2:
            continue
        w, h = img.size
        px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
        return (px[:, :, :3], w, h)
    return None


def voxelize(V, T, tri_col):
    lo = V.min(axis=0); hi = V.max(axis=0)
    size = np.maximum(hi - lo, 1e-6)
    cell = size.max() / RES
    dims = np.maximum(np.ceil(size / cell).astype(int), 1)
    # grid[node] accumulators
    nd = dims
    solid = np.zeros(tuple(dims), dtype=bool)
    colsum = np.zeros(tuple(nd) + (3,), dtype=float)
    cnt = np.zeros(tuple(nd), dtype=float)

    # rasterize triangles into the node lattice (fine for evaluation: barycentric sample)
    A = V[T]  # (M,3,3)
    # sample density proportional to triangle area in cells
    areas = 0.5 * np.linalg.norm(np.cross(A[:, 1] - A[:, 0], A[:, 2] - A[:, 0]), axis=1)
    dens = np.clip(np.ceil(areas / (cell * cell) * 2.0), 1, 64).astype(int)
    for ti in range(len(T)):
        d = dens[ti]
        n = max(2, int(math.ceil(math.sqrt(d * 2))))
        for i in range(n + 1):
            for j in range(n + 1 - i):
                w0 = i / n; w1 = j / n; w2 = 1.0 - w0 - w1
                p = A[ti, 0] * w0 + A[ti, 1] * w1 + A[ti, 2] * w2
                idx = np.floor((p - lo) / cell).astype(int)
                idx = np.clip(idx, 0, dims - 1)
                solid[idx[0], idx[1], idx[2]] = True
                colsum[idx[0], idx[1], idx[2]] += tri_col[ti]
                cnt[idx[0], idx[1], idx[2]] += 1.0

    if MODE == "solid":
        solid = fill_solid(solid)

    # colour per occupied voxel; fill gaps by nearest-neighbour dilation
    occ = cnt > 0
    colours = np.zeros(tuple(dims) + (3,), dtype=float)
    safe = np.maximum(cnt, 1)[..., None]
    colours[occ] = colsum[occ] / safe[occ]
    # voxels that ended up black (UV miss) inherit colour from their neighbours
    lum = colours.sum(axis=-1)
    known = occ & (lum > 0.04)
    if (~known).any():
        filled = propagate(colours, known)
        colours[~known] = filled[~known]
        # anything still black gets a neutral plastic grey
        still = colours.sum(axis=-1) < 0.04
        colours[still] = (0.62, 0.64, 0.68)

    vox = {"res": RES, "cell": cell, "origin": lo.tolist(),
           "dims": dims.tolist(), "solid": solid, "colours": colours}
    return vox


def fill_solid(solid):
    """Flood fill air from the border; everything not reached becomes solid."""
    from collections import deque
    dims = np.array(solid.shape)
    air = np.zeros_like(solid)
    q = deque()
    for x in range(dims[0]):
        for y in range(dims[1]):
            for z in (0, dims[2] - 1):
                if not solid[x, y, z] and not air[x, y, z]:
                    air[x, y, z] = True; q.append((x, y, z))
    for x in range(dims[0]):
        for z in range(dims[2]):
            for y in (0, dims[1] - 1):
                if not solid[x, y, z] and not air[x, y, z]:
                    air[x, y, z] = True; q.append((x, y, z))
    for y in range(dims[1]):
        for z in range(dims[2]):
            for x in (0, dims[0] - 1):
                if not solid[x, y, z] and not air[x, y, z]:
                    air[x, y, z] = True; q.append((x, y, z))
    while q:
        x, y, z = q.popleft()
        for dx, dy, dz in ((1,0,0),(-1,0,0),(0,1,0),(0,-1,0),(0,0,1),(0,0,-1)):
            nx, ny, nz = x+dx, y+dy, z+dz
            if 0 <= nx < dims[0] and 0 <= ny < dims[1] and 0 <= nz < dims[2]:
                if not solid[nx, ny, nz] and not air[nx, ny, nz]:
                    air[nx, ny, nz] = True
                    q.append((nx, ny, nz))
    return ~air


def propagate(colours, occ):
    """Cheap nearest-neighbour colour fill via iterative dilation."""
    cur = colours.copy()
    known = occ.copy()
    for _ in range(6):
        if known.all():
            break
        nxt = cur.copy(); nk = known.copy()
        for axis in range(3):
            for s in (1, -1):
                sh = np.roll(cur, s, axis=axis)
                sk = np.roll(known, s, axis=axis)
                take = (~nk) & sk
                nxt[take] = sh[take]
                nk |= take
        cur, known = nxt, nk
    return cur


def smooth_colours(colours, solid, passes=2):
    """Median-ish smoothing across neighbours: kills single-voxel colour speckle so
    merged boxes read as panels rather than confetti."""
    c = colours.copy()
    for _ in range(passes):
        acc = np.zeros_like(c)
        w = np.zeros(solid.shape, dtype=float)
        for axis in range(3):
            for sft in (-1, 0, 1):
                sh = np.roll(c, sft, axis=axis)
                acc += sh * 0.9
                w += 0.9
        mask = solid
        c[mask] = (acc[mask] / w[mask][:, None])
    return c


def greedy_mesh(solid, colours, cell, origin, min_share):
    """Greedy box merging over quantized colours. Returns list of boxes."""
    dims = solid.shape
    # quantize colours so merging is effective
    Q = (np.clip(colours, 0, 1) * 12).astype(int)
    key = Q[..., 0] * 169 + Q[..., 1] * 13 + Q[..., 2]
    key[~solid] = -1
    used = np.zeros(dims, dtype=bool)
    boxes = []
    for x in range(dims[0]):
        for y in range(dims[1]):
            for z in range(dims[2]):
                if used[x, y, z] or not solid[x, y, z]:
                    continue
                k = key[x, y, z]
                # extend along y
                y2 = y
                while y2 + 1 < dims[1] and solid[x, y2+1, z] and key[x, y2+1, z] == k and not used[x, y2+1, z]:
                    y2 += 1
                # extend along z
                z2 = z
                ok = True
                while ok and z2 + 1 < dims[2]:
                    for yy in range(y, y2 + 1):
                        if not (solid[x, yy, z2+1] and key[x, yy, z2+1] == k and not used[x, yy, z2+1]):
                            ok = False; break
                    if ok:
                        z2 += 1
                # extend along x
                x2 = x
                ok = True
                while ok and x2 + 1 < dims[0]:
                    for yy in range(y, y2 + 1):
                        for zz in range(z, z2 + 1):
                            if not (solid[x2+1, yy, zz] and key[x2+1, yy, zz] == k and not used[x2+1, yy, zz]):
                                ok = False; break
                        if not ok: break
                    if ok:
                        x2 += 1
                used[x:x2+1, y:y2+1, z:z2+1] = True
                c = colours[(x + x2) // 2, (y + y2) // 2, (z + z2) // 2]
                boxes.append({
                    "min": origin + np.array([x, y, z]) * cell,
                    "size": np.array([x2 - x + 1, y2 - y + 1, z2 - z + 1]) * cell,
                    "col": [float(c[0]), float(c[1]), float(c[2])],
                })
    # drop slivers
    total = sum(b["size"].prod() for b in boxes) or 1.0
    boxes = [b for b in boxes if b["size"].prod() / total > min_share] or boxes
    return boxes


def emit(boxes):
    return [{"c": [round(float(v), 4) for v in b["min"] + b["size"] / 2],
             "s": [round(float(v), 4) for v in b["size"]],
             "col": [round(min(1.0, max(0.0, v)) ** 2.2, 4) for v in b["col"]]} for b in boxes]


def run_group(V, T, tri_col, group=None):
    if group is not None:
        mask = np.zeros(len(T), dtype=bool)
        sel = (T[:, 0] >= group["v0"]) & (T[:, 0] < group["v1"])
        T2 = T[sel]
        if len(T2) == 0:
            return [], None
        tri2 = tri_col[sel]
    else:
        T2, tri2 = T, tri_col
    if len(T2) == 0:
        return [], None
    vox = voxelize(V, T2, tri2)
    colours = smooth_colours(vox["colours"], vox["solid"], passes=2)
    boxes = greedy_mesh(vox["solid"], colours, vox["cell"], np.array(vox["origin"]), MIN_SHARE)
    return emit(boxes), T2


def main():
    objs = load(SRC)
    if not objs:
        raise SystemExit("no meshes in " + SRC)
    V, T, TM, C, groups = mesh_data(objs)
    tex = get_texture()
    tri_col = sample_colours(V, T, C, tex)
    lo = V.min(axis=0); hi = V.max(axis=0)

    body_boxes, _ = run_group(V, T, tri_col)
    body = {"name": "body", "kind": "body", "pivot": [0, 0, 0], "size": (hi - lo).tolist(),
            "boxes": body_boxes}

    wheels = []
    for g in groups:
        if g["kind"] != "wheel":
            continue
        # wheels are rebuilt procedurally in-engine (real cylinders on hinge motors)
        boxes, T2 = [], None
        gv = V[g["v0"]:g["v1"]]
        gmn, gmx = gv.min(axis=0), gv.max(axis=0)
        pivot = ((gmn + gmx) / 2).tolist()
        wheels.append({"name": g["name"], "kind": "wheel", "pivot": pivot,
                       "size": (gmx - gmn).tolist(), "boxes": boxes})

    data = {
        "source": os.path.basename(SRC), "mode": MODE, "res": RES,
        "bbox_min": lo.tolist(), "bbox_max": hi.tolist(),
        "size": (hi - lo).tolist(), "tris": int(len(T)),
        "body": body, "wheels": wheels,
        # flattened list kept for single-model renders / older tooling
        "boxes": body_boxes + [b for w in wheels for b in w["boxes"]],
    }
    with open(OUT, "w") as f:
        json.dump(data, f)
    print("VOX %s body=%d wheels=%d tris=%d size=%.2f,%.2f,%.2f" %
          (os.path.basename(SRC), len(body_boxes), len(wheels), len(T), *data["size"]))


main()


main()
