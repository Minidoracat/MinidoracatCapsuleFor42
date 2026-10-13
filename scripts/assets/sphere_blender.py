#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""帕魯球（MinidoracatSphere）的 Blender headless 產線（Blender 5.2），由 build_sphere.py 呼叫。

用法（由 repo 根目錄執行）：
    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
      --python scripts/assets/sphere_blender.py -- temp/sphere-art/config.json

config.json：here、media、out、rects、tex、icon_view、atlases（[{path, emit}]）。
產物：media/models_X/WorldItems/MinidoracatSphere.fbx（四級共用一個 mesh）、每張 atlas 一張
out/icon_<stem>.png（256 px 透明算圖；有 emit 的再多一張無光照 out/icon_<stem>_emit.png）、
out/model_<stem>.png（EEVEE 預覽）與 out/fbx_verify.txt。

座標：公尺；球平躺，上下尖頂沿 ±X，正面尖形飾片朝 +Z（放在地上時朝天），原點在底面中心
（玻璃球最低點 z=0）。相機、匯出參數與 capsule_blender.py 共用（直接 import）。
"""

import json
import math
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector

CFG = json.loads(Path(sys.argv[sys.argv.index("--") + 1]).read_text(encoding="utf-8"))
sys.path.insert(0, CFG["here"])
import capsule_blender as cb  # noqa: E402

PI = math.pi
N = 32            # 繞 X 軸的段數
LAT = 16          # 玻璃球極到極的段數
R = 0.016         # 玻璃球半徑
ZC = R            # 球心高度（最低點 z=0）
TIP = 0.0255     # 尖頂到球心的距離
SPIKE = 0.005     # 飾片尖端高出球面
# 尖頂輪廓（+X 側，x 遞增）；前兩環在玻璃內，球面以外是領圈、細頸、球節、尖錐。
FINIAL = ((0.0142, 0.0056), (0.0144, 0.0062), (0.0160, 0.0062), (0.0165, 0.0048),
          (0.0172, 0.0036), (0.0178, 0.0044), (0.0188, 0.0047), (0.0197, 0.0042),
          (0.0201, 0.0032), (0.0204, 0.0036), (TIP, 0.0))
# 飾片：四角星底（長角沿 STAR_ANGLE＝build_sphere 第一條斜框的方向、短角垂直、45° 內凹），貼在球頂。
STAR = (0.0105, 0.0024, 0.0055, 0.0024, 0.0105, 0.0024, 0.0055, 0.0024)
STAR_ANGLE = math.radians(28)
EXPECTED_DIMS = (2 * TIP, 2 * R, 2 * R + SPIKE)

verts, faces, face_uvs, flat = [], [], [], []


def add_vertex(co):
    verts.append(tuple(co))
    return len(verts) - 1


def add_face(inds, uvs, smooth=True):
    faces.append(list(inds))
    face_uvs.append(list(uvs))
    flat.append(not smooth)


def revolve(profile, rect):
    """profile=[(x, r, v)] 沿 X 旋轉；r=0 用單一極點。UV u=j/N 不回繞（接縫有獨立 UV）。"""
    tex = CFG["tex"]
    rings = []
    for x, r, _ in profile:
        if r <= 1e-9:
            rings.append([add_vertex((x, 0.0, ZC))])
        else:
            rings.append([add_vertex((x, r * math.sin(2 * PI * j / N), ZC - r * math.cos(2 * PI * j / N)))
                          for j in range(N)])
    uv = lambda j, i: cb.rect_uv(rect, tex, j / N, profile[i][2])  # noqa: E731
    for i in range(len(rings) - 1):
        a, b = rings[i], rings[i + 1]
        for j in range(N):
            j1 = (j + 1) % N
            if len(a) == 1:
                add_face([a[0], b[j1], b[j]], [uv(j + 0.5, i), uv(j + 1, i + 1), uv(j, i + 1)])
            elif len(b) == 1:
                add_face([a[j1], a[j], b[0]], [uv(j + 1, i), uv(j, i), uv(j + 0.5, i + 1)])
            else:
                add_face([a[j], a[j1], b[j1], b[j]], [uv(j, i), uv(j + 1, i), uv(j + 1, i + 1), uv(j, i + 1)])


def arc_v(points):
    """輪廓累積弧長正規化成 v。"""
    acc = [0.0]
    for (x0, r0), (x1, r1) in zip(points, points[1:]):
        acc.append(acc[-1] + math.hypot(x1 - x0, r1 - r0))
    return [(x, r, a / acc[-1]) for (x, r), a in zip(points, acc)]


def build_sphere():
    rects = CFG["rects"]
    tex = CFG["tex"]
    glass = []
    for k in range(LAT + 1):
        phi = PI * k / LAT
        glass.append((-R * math.cos(phi), R * math.sin(phi) if 0 < k < LAT else 0.0, k / LAT))
    revolve(glass, rects["glass"])
    plus = arc_v(FINIAL)
    revolve(plus, rects["brass"])
    revolve([(-x, r, v) for x, r, v in reversed(plus)], rects["brass"])

    # 飾片：底邊投影到略低於球面處（邊緣埋進玻璃），尖端在球頂上方 SPIKE。
    base = []
    ouv = []
    for k, rad in enumerate(STAR):
        b = 2 * PI * k / len(STAR) + STAR_ANGLE
        x, y = rad * math.cos(b), rad * math.sin(b)
        p = Vector((x, y, math.sqrt(R * R - x * x - y * y))).normalized() * (R - 0.0003)
        base.append(add_vertex((p.x, p.y, p.z + ZC)))
        ouv.append(cb.rect_uv(rects["ornament"], tex, 0.5 + 0.5 * rad / STAR[0] * math.cos(b),
                              0.5 - 0.5 * rad / STAR[0] * math.sin(b)))
    apex = add_vertex((0.0, 0.0, ZC + R + SPIKE))
    centre = cb.rect_uv(rects["ornament"], tex, 0.5, 0.5)
    for k in range(len(STAR)):
        k1 = (k + 1) % len(STAR)
        add_face([base[k], base[k1], apex], [ouv[k], ouv[k1], centre], smooth=False)

    me = bpy.data.meshes.new("MinidoracatSphereMesh")
    me.from_pydata(verts, [], faces)
    bm = bmesh.new()
    bm.from_mesh(me)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    uv_layer = me.uv_layers.new(name="UVMap")
    for poly, uvs, is_flat in zip(me.polygons, face_uvs, flat):
        poly.use_smooth = not is_flat
        for li, co in zip(poly.loop_indices, uvs):
            uv_layer.data[li].uv = co
    me.update()
    mat = bpy.data.materials.new("MinidoracatSphereMaterial")
    mat.use_nodes = True
    mat.use_backface_culling = False
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Roughness"].default_value = 0.45
    tex_node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    tex_node.image = bpy.data.images.load(CFG["atlases"][0]["path"], check_existing=True)
    mat.node_tree.links.new(tex_node.outputs["Color"], bsdf.inputs["Base Color"])
    me.materials.append(mat)
    ob = bpy.data.objects.new("MinidoracatSphere", me)
    bpy.context.scene.collection.objects.link(ob)
    return ob, tex_node


def render_icon(ob, out_path, emissive=False):
    """膠囊 render_icon 的球版：同樣 Workbench、256 px 透明；相機角度來自 config（外層畫核心光也用它）。"""
    sc = bpy.context.scene
    cb.hide_all_meshes(ob)
    vs = sc.view_settings
    vs.view_transform, vs.look, vs.exposure = ("Standard", "None", 0.0)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "FLAT" if emissive else "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = False
    sc.display.shading.show_cavity = not emissive
    sc.display.shading.cavity_type = "WORLD"
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x = sc.render.resolution_y = 256
    sc.render.resolution_percentage = 100
    lo, hi = cb.bbox(ob)
    view = CFG["icon_view"]
    cam = cb.look_camera((lo + hi) * 0.5, az=view["az"], el=view["el"], distance=0.35, roll=view["roll"])
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 0.08
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def verify_fbx(path, review_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    unit = cb.parse_unitscale(path)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    imported = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    if len(imported) != 1:
        raise RuntimeError(f"FBX re-import: expected one mesh, got {len(imported)}")
    ob = imported[0]
    origin = tuple(float(v) for v in ob.matrix_world.translation)
    if max(abs(v) for v in origin) > 1e-4:
        raise RuntimeError(f"FBX origin moved: {origin}")
    dims = tuple(float(x) / (unit / 100.0) for x in ob.dimensions)
    tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    if max(abs(a - b) for a, b in zip(sorted(dims), sorted(EXPECTED_DIMS))) > 0.0015:
        raise RuntimeError(f"FBX dimension mismatch {dims} != {EXPECTED_DIMS}")
    if tri > 3000 or len(ob.data.uv_layers) < 1 or len(ob.data.materials) != 1:
        raise RuntimeError("FBX contract failed: <=3000 triangles, UV, one material")
    lines = [f"UnitScaleFactor={unit}", f"object={ob.name}", f"origin_translation={origin}",
             f"normalized_dimensions_m={dims}", f"expected_m={EXPECTED_DIMS}", f"triangles={tri}",
             f"vertices={len(ob.data.vertices)}", f"uv_layers={len(ob.data.uv_layers)}",
             f"materials={len(ob.data.materials)}", "ASSERT=PASS one_mesh dimensions triangles uv material"]
    Path(review_path).write_text("\n".join(lines) + "\n", encoding="utf-8", newline="\n")
    print("FBX VERIFY OK", review_path)


def main():
    out = Path(CFG["out"])
    out.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ob, tex_node = build_sphere()
    fbx = Path(CFG["media"]) / "models_X/WorldItems/MinidoracatSphere.fbx"
    fbx.parent.mkdir(parents=True, exist_ok=True)
    cb.export_fbx(ob, str(fbx))
    for entry in CFG["atlases"]:
        stem = Path(entry["path"]).stem
        cb.set_texture(tex_node, entry["path"])
        render_icon(ob, str(out / f"icon_{stem}.png"))
        cb.render_model(ob, str(out / f"model_{stem}.png"))
        cb.set_texture(tex_node, entry["emit"])  # 無光照的發光層，外層以 lighter 疊回
        render_icon(ob, str(out / f"icon_{stem}_emit.png"), emissive=True)
    verify_fbx(str(fbx), str(out / "fbx_verify.txt"))
    print("BUILD OK", fbx)


main()
