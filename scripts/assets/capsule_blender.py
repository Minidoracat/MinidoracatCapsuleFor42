#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Universal Capsule 的 Blender headless 產線（Blender 5.2）。

用法（由 repo 根目錄執行）：
    "C:/Program Files/Blender Foundation/Blender 5.2/blender.exe" -b --factory-startup \
      --python scripts/assets/capsule_blender.py -- \
      temp/assets-model/config.json

config.json 必須提供 repo、media、out、review、atlas（含 empty/loaded/icons/size/rects）。
產物：media/models_X/WorldItems/MinidoracatCapsule.fbx（所有型號共用一個 mesh）、
atlas.icons 每張 512px 貼圖各一張 out/icon_<atlas 檔名>.png（外層腳本會安裝至 media/textures/；
有 emit 的再多一張無光照的 out/icon_<atlas 檔名>_emit.png 供外層疊上發光花紋），
以及 review 中用 atlas.empty/loaded 算的 model_*.png、side_neg_y.png、side_pos_y.png、
ground_*.png 與 fbx_verify.txt。座標為公尺，膠囊長軸沿 +X，原點在
底面中心（最低 z=0）；圓周 32 段、半球 8 段。貼圖的文字只由外層 PIL 畫入，字型為
Barlow-SemiBold.ttf（SIL Open Font License 1.1，全文在 scripts/assets/fonts/OFL-Barlow.txt）。
"""

import json
import math
import os
import sys
from pathlib import Path

import bpy
import bmesh
from mathutils import Vector, Quaternion


PI = math.pi
RING_N = 32
HEMI_N = 8
RADIUS = 0.0135
CYL_MIN = -0.0215
CYL_MAX = 0.0195
SHELL_LEFT_TIP = -0.035
SHELL_RIGHT_TIP = 0.033
BUTTON_TIP = 0.035
Z_CENTER = RADIUS


def rect_uv(rect, tex, u, v):
    """Knox Pass 相同的矩形 UV（PIL 左上原點，Blender V 軸向上）。"""
    x0, y0, x1, y1 = rect
    return ((x0 + u * (x1 - x0)) / tex, 1.0 - (y0 + v * (y1 - y0)) / tex)


def swatch(rect, tex, u, v):
    return rect_uv(rect, tex, u, v)


class MeshBuilder:
    """共享環頂點並逐 loop 寫 UV；shared vertices + smooth polygons 讓外殼平滑。"""

    def __init__(self):
        self.vertices = []
        self.faces = []
        self.face_uvs = []

    def add_vertex(self, co):
        self.vertices.append(tuple(co))
        return len(self.vertices) - 1

    def add_face(self, inds, uv):
        self.faces.append(list(inds))
        self.face_uvs.append(list(uv))

    def ring_surface(self, profile, uv_func):
        """沿 X 軸旋轉 profile=(x,rad)；rad=0 ring 用單一 pole vertex。"""
        rings = []
        for x, rad, kind in profile:
            if rad <= 1e-8:
                rings.append([self.add_vertex((x, 0.0, Z_CENTER))])
            else:
                rings.append([
                    self.add_vertex((x, rad * math.sin(2 * PI * j / RING_N),
                                     Z_CENTER - rad * math.cos(2 * PI * j / RING_N)))
                    for j in range(RING_N)
                ])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if len(a) == 1 and len(b) == RING_N:
                pole = a[0]
                for j in range(RING_N):
                    j1 = (j + 1) % RING_N
                    inds = [pole, b[j1], b[j]]
                    self.add_face(inds, [uv_func(i, j, 0), uv_func(i, j1, 0), uv_func(i, j, 0)])
            elif len(a) == RING_N and len(b) == 1:
                pole = b[0]
                for j in range(RING_N):
                    j1 = (j + 1) % RING_N
                    # At the +X pole the outward normal points along +X;
                    # reverse the closing fan so the hemisphere is not
                    # backface-culled as a dark hole in EEVEE.
                    inds = [a[j1], a[j], pole]
                    self.add_face(inds, [uv_func(i, j1, 0), uv_func(i, j, 0), uv_func(i, j, 0)])
            else:
                for j in range(RING_N):
                    j1 = (j + 1) % RING_N
                    # theta × +X gives outward normal for the z=0 bottom point.
                    inds = [a[j], a[j1], b[j1], b[j]]
                    self.add_face(inds, [uv_func(i, j, 0), uv_func(i, j1, 0),
                                         uv_func(i, j1, 1), uv_func(i, j, 1)])

    def button_surface(self, profile, uv_func):
        # Button has 16 radial segments to keep the whole object comfortably under 3k tris.
        n = 16
        rings = []
        for x, rad, kind in profile:
            if rad <= 1e-8:
                rings.append([self.add_vertex((x, 0.0, Z_CENTER))])
            else:
                rings.append([
                    self.add_vertex((x, rad * math.sin(2 * PI * j / n),
                                     Z_CENTER - rad * math.cos(2 * PI * j / n)))
                    for j in range(n)
                ])
        # Close the button's recessed base.  Without this small -X disk the
        # open side wall can reveal the cylinder atlas behind it in EEVEE.
        if rings and len(rings[0]) == n:
            base_center = self.add_vertex((profile[0][0], 0.0, Z_CENTER))
            for j in range(n):
                j1 = (j + 1) % n
                self.add_face([base_center, rings[0][j1], rings[0][j]],
                              [uv_func(0, j), uv_func(0, j1), uv_func(0, j)])
        for i in range(len(rings) - 1):
            a, b = rings[i], rings[i + 1]
            if len(a) == 1:
                for j in range(n):
                    j1 = (j + 1) % n
                    self.add_face([a[0], b[j1], b[j]], [uv_func(i, j), uv_func(i, j1), uv_func(i, j)])
            elif len(b) == 1:
                for j in range(n):
                    j1 = (j + 1) % n
                    # The +X button top faces point out along the axis.  The
                    # reversed winding keeps their normals consistent with
                    # the capsule cap and prevents a backface hole in EEVEE.
                    self.add_face([a[j1], a[j], b[0]], [uv_func(i, j1), uv_func(i, j), uv_func(i, j)])
            else:
                for j in range(n):
                    j1 = (j + 1) % n
                    self.add_face([a[j], a[j1], b[j1], b[j]],
                                  [uv_func(i, j), uv_func(i, j1), uv_func(i, j1), uv_func(i, j)])

    def make_object(self, name, image):
        me = bpy.data.meshes.new(name + "Mesh")
        me.from_pydata(self.vertices, [], self.faces)
        # Build-time winding is easy to get wrong at a pole.  Recalculate
        # connected face normals so EEVEE cannot cull a cap as a hole.
        bm = bmesh.new()
        bm.from_mesh(me)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
        bm.to_mesh(me)
        bm.free()
        me.update()
        uv_layer = me.uv_layers.new(name="UVMap")
        for poly in me.polygons:
            # capsule/button side surfaces smooth; tiny button top and seam remain visually crisp via geometry/texture.
            poly.use_smooth = True
        for poly, uv in zip(me.polygons, self.face_uvs):
            for li, co in zip(poly.loop_indices, uv):
                uv_layer.data[li].uv = co
        mat = bpy.data.materials.new(name + "Material")
        mat.use_nodes = True
        mat.use_backface_culling = False
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        bsdf.inputs["Roughness"].default_value = 0.62
        tex = mat.node_tree.nodes.new("ShaderNodeTexImage")
        tex.name = "CapsuleAtlas"
        tex.image = image
        mat.node_tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
        me.materials.append(mat)
        ob = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(ob)
        return ob, mat, tex


def build_capsule(rects, tex_size, image):
    mb = MeshBuilder()
    cyl_rect = rects["cylinder"]
    minus_rect = rects["cap_minus"]
    plus_rect = rects["cap_plus"]
    seam_rect = rects["seam"]
    button_rect = rects["button"]
    button_side_rect = rects["button_side"]

    # Profile includes the recessed +X seam: 1.2 mm wide, 0.3 mm radial inset.
    # True hemispheres (eight axial intervals each), plus the recessed +X seam.
    # The shell center line is z=RADIUS, so its lowest point remains exactly z=0.
    profile = []
    for k in range(HEMI_N + 1):
        phi = (PI * 0.5) * (1.0 - k / HEMI_N)
        profile.append((CYL_MIN - RADIUS * math.sin(phi),
                        RADIUS * math.cos(phi),
                        "cap_minus" if k < HEMI_N else "cylinder"))
    profile += [
        (CYL_MAX - 0.0018, RADIUS, "cylinder"),
        (CYL_MAX - 0.0012, RADIUS - 0.0003, "seam"),
        (CYL_MAX, RADIUS - 0.0003, "seam"),
        # Leave a 0.2 mm axial shoulder after the recessed groove before the
        # cap UV begins; this keeps the dark seam swatch from spilling over
        # the hemisphere in EEVEE's interpolated shading.
        (CYL_MAX + 0.0002, RADIUS, "cap_plus"),
    ]
    for k in range(1, HEMI_N + 1):
        phi = (PI * 0.5) * (k / HEMI_N)
        x = CYL_MAX + 0.0002 + (RADIUS - 0.0002) * math.sin(phi)
        profile.append((x, RADIUS * math.cos(phi) if k < HEMI_N else 0.0, "cap_plus"))

    def shell_uv(i, j, end):
        x0, r0, kind = profile[i]
        x1, r1, _ = profile[min(i + 1, len(profile) - 1)]
        theta = j / RING_N
        if kind == "cylinder":
            v0 = max(0.0, min(1.0, (x0 - CYL_MIN) / (CYL_MAX - CYL_MIN)))
            v1 = max(0.0, min(1.0, (x1 - CYL_MIN) / (CYL_MAX - CYL_MIN)))
            return rect_uv(cyl_rect, tex_size, theta, v0 if end == 0 else v1)
        if kind == "seam":
            return rect_uv(seam_rect, tex_size, theta, (0.0 if end == 0 else 1.0))
        if kind == "cap_minus":
            # Polar projection: y/r and (z-R)/r, as requested by the atlas contract.
            x, r = (x0, r0) if end == 0 else (x1, r1)
            if r < 1e-8:
                py, pz = 0.0, 1.0
            else:
                py = (r * math.sin(2 * PI * j / RING_N)) / RADIUS
                pz = (Z_CENTER - r * math.cos(2 * PI * j / RING_N) - Z_CENTER) / RADIUS
            return rect_uv(minus_rect, tex_size, (py + 1) * 0.5, (pz + 1) * 0.5)
        # +X cap, same projection but distinct atlas rectangle.
        x, r = (x0, r0) if end == 0 else (x1, r1)
        if r < 1e-8:
            py, pz = 0.0, 1.0
        else:
            py = (r * math.sin(2 * PI * j / RING_N)) / RADIUS
            pz = (Z_CENTER - r * math.cos(2 * PI * j / RING_N) - Z_CENTER) / RADIUS
        return rect_uv(plus_rect, tex_size, (py + 1) * 0.5, (pz + 1) * 0.5)

    mb.ring_surface(profile, shell_uv)

    # Button: little beveled brushed-metal puck, axis +X, tip at +0.035 m.
    bprof = [
        (0.0307, 0.0037, "side"),
        (0.0310, 0.0045, "side"),
        (0.0343, 0.0045, "side"),
        (0.0348, 0.0042, "side"),
        (BUTTON_TIP, 0.0, "top"),
    ]

    def button_uv(i, j):
        kind = bprof[i][2]
        if kind == "top" or (i == len(bprof) - 2 and bprof[i + 1][1] <= 1e-8):
            # end cap: disk coordinates in the button atlas tile
            u = (math.sin(2 * PI * j / 16) + 1.0) * 0.5
            v = (1.0 - math.cos(2 * PI * j / 16)) * 0.5
            return rect_uv(button_rect, tex_size, u, v)
        return rect_uv(button_side_rect, tex_size, j / 16.0, 0.5)

    mb.button_surface(bprof, button_uv)
    ob, mat, tex = mb.make_object("MinidoracatCapsule", image)
    return ob, mat, tex


def texture_from_material(mat):
    for node in mat.node_tree.nodes:
        if node.type == "TEX_IMAGE":
            return node
    return None


def set_texture(tex_node, path):
    img = bpy.data.images.load(path, check_existing=True)
    tex_node.image = img
    return img


def look_camera(target, az, el, distance, roll=0.0):
    a, e = math.radians(az), math.radians(el)
    cam_data = bpy.data.cameras.new("CapsuleCamera")
    cam = bpy.data.objects.new("CapsuleCamera", cam_data)
    bpy.context.scene.collection.objects.link(cam)
    cam.location = Vector(target) + Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * distance
    q = (Vector(target) - cam.location).to_track_quat("-Z", "Y")
    if roll:
        q = q @ Quaternion((0.0, 0.0, 1.0), math.radians(roll))
    cam.rotation_euler = q.to_euler()
    bpy.context.scene.camera = cam
    return cam


def hide_all_meshes(visible):
    for ob in bpy.context.scene.objects:
        if ob.type == "MESH":
            ob.hide_render = ob is not visible


# Colour management per icon variant.  The approved icons were rendered with
# Blender's factory grade for the empty capsule and the model-preview grade for
# the loaded one (darker body, so the band reads); keep both explicit.  The
# emissive pass (glow/sparkle mask atlas) is unlit and ungraded so a white texel
# stays white; the outer builder merges it with ImageChops.lighter.
ICON_GRADE = {False: ("AgX", "None", 0.0), True: ("Standard", "Medium High Contrast", -1.25)}
EMIT_GRADE = ("Standard", "None", 0.0)


def render_icon(ob, out_path, loaded, emissive=False, ortho=0.095):
    sc = bpy.context.scene
    hide_all_meshes(ob)
    vs = sc.view_settings
    vs.view_transform, vs.look, vs.exposure = EMIT_GRADE if emissive else ICON_GRADE[loaded]
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
    lo, hi = bbox(ob)
    target = (lo + hi) * 0.5
    # View from the +X/button end so the metal puck remains visible; the
    # negative roll puts the long axis on the icon diagonal.
    # A side-biased +X view keeps the button visible while projecting the
    # long axis diagonally instead of hiding it down the camera axis.
    cam = look_camera(target, az=55, el=31, distance=0.35, roll=-20)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = ortho
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)


def render_side_views(ob, neg_path, pos_path):
    """輸出只供人工檢查的 -Y／+Y 正交側視圖。"""
    sc = bpy.context.scene
    hide_all_meshes(ob)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = False
    sc.display.shading.show_cavity = True
    sc.display.shading.cavity_type = "WORLD"
    sc.render.film_transparent = False
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x, sc.render.resolution_y = 800, 400
    sc.render.resolution_percentage = 100
    lo, hi = bbox(ob)
    target = (lo + hi) * 0.5
    for az, out_path in ((-90, neg_path), (90, pos_path)):
        cam = look_camera(target, az=az, el=0, distance=0.2)
        cam.data.type = "ORTHO"
        cam.data.ortho_scale = 0.045
        sc.camera = cam
        sc.render.filepath = out_path
        bpy.ops.render.render(write_still=True)
        bpy.data.objects.remove(cam, do_unlink=True)


def bbox(ob):
    pts = [Vector(v.co) for v in ob.data.vertices]
    return Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts))), Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))


def render_model(ob, out_path, loaded=False):
    sc = bpy.context.scene
    hide_all_meshes(ob)
    # Blender has used both identifiers across 5.x builds; choose the enum
    # exposed by this exact headless binary instead of assuming a UI label.
    for candidate in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT", "CYCLES"):
        try:
            sc.render.engine = candidate
            break
        except (TypeError, ValueError):
            continue
    else:
        raise RuntimeError("Blender 沒有可用的 EEVEE/Cycles render engine")
    sc.render.resolution_x, sc.render.resolution_y = 1024, 768
    sc.render.resolution_percentage = 100
    sc.render.film_transparent = False
    if sc.world is None:
        sc.world = bpy.data.worlds.new("CapsulePreviewWorld")
    sc.world.color = (0.015, 0.017, 0.02)
    sc.world.use_nodes = True
    bg = sc.world.node_tree.nodes.get("Background")
    if bg:
        bg.inputs["Color"].default_value = (0.012, 0.015, 0.02, 1.0)
        bg.inputs["Strength"].default_value = 0.18
    sc.view_settings.view_transform = "Standard"
    try:
        sc.view_settings.look = "Medium High Contrast"
    except (TypeError, ValueError):
        pass
    sc.view_settings.exposure = -1.25
    if sc.world.use_nodes:
        bg = sc.world.node_tree.nodes.get("Background")
        if bg:
            bg.inputs["Color"].default_value = (0.015, 0.017, 0.02, 1.0)
            bg.inputs["Strength"].default_value = 0.35
    # Matte charcoal ground.
    bpy.ops.mesh.primitive_plane_add(size=1.0, location=(0, 0, -0.0004))
    floor = bpy.context.object
    floor.name = "PreviewGround"
    fm = bpy.data.materials.new("PreviewGroundMaterial")
    fm.diffuse_color = (0.006, 0.007, 0.009, 1.0)
    fm.use_nodes = True
    fbs = fm.node_tree.nodes.get("Principled BSDF")
    fbs.inputs["Base Color"].default_value = (0.006, 0.007, 0.009, 1.0)
    fbs.inputs["Roughness"].default_value = 0.84
    floor.data.materials.append(fm)
    # Large area key from upper left and soft fill.
    bpy.ops.object.light_add(type="AREA", location=(-0.09, -0.13, 0.11))
    key = bpy.context.object
    key.data.energy = 2.0
    key.data.shape = "DISK"
    key.data.size = 0.12
    key.rotation_euler = (math.radians(22), 0.0, math.radians(-28))
    # Put the key on the +X/button side so the metal puck reads in the
    # 3/4 preview instead of falling into the end-cap shadow.
    key.location.x = 0.09
    bpy.ops.object.light_add(type="AREA", location=(0.08, 0.08, 0.06))
    fill = bpy.context.object
    fill.data.energy = 0.25
    fill.data.size = 0.16
    lo, hi = bbox(ob)
    target = Vector((0.0, 0.0, (lo.z + hi.z) * 0.54))
    # Keep the +X button end in the human-facing preview as well.
    cam = look_camera(target, az=80, el=18, distance=0.12)
    cam.data.type = "PERSP"
    cam.data.lens = 52
    sc.camera = cam
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    for x in (floor, key, fill, cam):
        bpy.data.objects.remove(x, do_unlink=True)


def render_ground(ob, out_path):
    sc = bpy.context.scene
    hide_all_meshes(ob)
    old_scale = ob.scale.copy()
    ob.scale = (3.0, 3.0, 3.0)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = False
    sc.render.film_transparent = True
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.render.resolution_x = sc.render.resolution_y = 64
    sc.render.resolution_percentage = 100
    lo, hi = bbox(ob)
    # bbox() is in object local coordinates; account for the requested model script scale.
    target = (lo + hi) * 0.5 * 3.0
    cam = look_camera(target, az=45, el=30, distance=0.45)
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 64.0 / 90.5
    sc.camera = cam
    sc.render.filepath = out_path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam, do_unlink=True)
    ob.scale = old_scale


def export_fbx(ob, path):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    # Keep these kwargs byte-for-byte aligned with the requested Knox Pass pipeline.
    bpy.ops.export_scene.fbx(filepath=path, use_selection=True, object_types={"MESH"}, apply_scale_options="FBX_SCALE_UNITS", bake_space_transform=True, axis_forward="-Z", axis_up="Y", mesh_smooth_type="FACE", add_leaf_bones=False, bake_anim=False, path_mode="STRIP")


def parse_unitscale(path):
    try:
        from io_scene_fbx import import_fbx, parse_fbx
        elem_root, _ = parse_fbx.parse(path)
        settings = import_fbx.elem_find_first(elem_root, b"GlobalSettings")
        props = import_fbx.elem_find_first(settings, b"Properties70")
        return float(import_fbx.elem_props_get_number(props, b"UnitScaleFactor", 1.0))
    except Exception as exc:
        print("FBX UnitScaleFactor parse warning:", exc)
        return 1.0


def verify_fbx(path, expected_ob, review_path):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    unit = parse_unitscale(path)
    result = bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False)
    imported = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    lines = [f"import_result={result}", f"UnitScaleFactor={unit}", f"normalization_factor=UnitScaleFactor/100={unit / 100.0}"]
    if not imported:
        raise RuntimeError("FBX re-import produced no mesh")
    ob = imported[0]
    origin_translation = tuple(float(v) for v in ob.matrix_world.translation)
    if max(abs(v) for v in origin_translation) > 1e-4:
        raise RuntimeError(f"FBX origin moved: matrix translation={origin_translation}")
    tri = sum(len(p.vertices) - 2 for p in ob.data.polygons)
    dims = tuple(float(x) for x in ob.dimensions)
    raw_dims = dims
    normalized = tuple(x / (unit / 100.0) for x in raw_dims)
    xs = [v.co.x for v in ob.data.vertices]
    ys = [v.co.y for v in ob.data.vertices]
    zs = [v.co.z for v in ob.data.vertices]
    image_names = []
    for material in ob.data.materials:
        if material and material.use_nodes:
            image_names.extend(node.image.name for node in material.node_tree.nodes
                               if node.type == "TEX_IMAGE" and node.image)
    lines += [f"object={ob.name}", f"matrix_world={tuple(tuple(round(c, 9) for c in row) for row in ob.matrix_world)}",
              f"origin_translation={origin_translation}",
              f"raw_dimensions={raw_dims}", f"normalized_dimensions_m={normalized}",
              f"bbox_min=({min(xs)}, {min(ys)}, {min(zs)})", f"bbox_max=({max(xs)}, {max(ys)}, {max(zs)})",
              f"triangles={tri}", f"vertices={len(ob.data.vertices)}", f"uv_layers={len(ob.data.uv_layers)}",
              f"materials={len(ob.data.materials)}", f"texture_names={image_names}"]
    # FBX importer can apply a rotation; compare axis-independent sorted dimensions.
    target = sorted((0.070, 0.027, 0.027))
    actual = sorted(normalized)
    if max(abs(a - b) for a, b in zip(actual, target)) > 0.0015:
        raise RuntimeError(f"FBX dimension mismatch normalized={normalized} target={target}")
    if len(imported) != 1 or tri > 3000 or len(ob.data.uv_layers) < 1 or len(ob.data.materials) != 1:
        raise RuntimeError("FBX contract failed: expected one mesh, <=3000 triangles, UV, one material")
    lines.append("ASSERT=PASS one_mesh dimensions triangles uv material")
    Path(review_path).write_text("\n".join(lines) + "\n", encoding="utf-8")
    print("FBX VERIFY OK", review_path)


def main():
    if "--" not in sys.argv:
        raise SystemExit("missing config path after --")
    cfg = json.loads(Path(sys.argv[sys.argv.index("--") + 1]).read_text(encoding="utf-8"))
    # Honour the geometry contract supplied by the outer PIL builder while keeping
    # the documented thumb-sized defaults for hand-written configs.
    geom = cfg.get("geometry", {})
    global RADIUS, CYL_MIN, CYL_MAX, BUTTON_TIP, SHELL_LEFT_TIP, SHELL_RIGHT_TIP, RING_N, HEMI_N
    RADIUS = float(geom.get("radius", RADIUS))
    CYL_MIN = float(geom.get("cylinder_min", CYL_MIN))
    CYL_MAX = float(geom.get("cylinder_max", CYL_MAX))
    BUTTON_TIP = float(geom.get("button_tip", BUTTON_TIP))
    SHELL_LEFT_TIP = CYL_MIN - RADIUS
    SHELL_RIGHT_TIP = CYL_MAX + RADIUS
    RING_N = int(geom.get("segments", RING_N))
    HEMI_N = int(geom.get("hemisphere_segments", HEMI_N))
    media = Path(cfg["media"])
    out = Path(cfg["out"])
    review = Path(cfg["review"])
    out.mkdir(parents=True, exist_ok=True)
    review.mkdir(parents=True, exist_ok=True)
    atlas = cfg["atlas"]
    tex_size = int(atlas.get("size", 512))
    rects = atlas.get("rects", atlas)
    empty_path = Path(atlas["empty"])
    loaded_path = Path(atlas["loaded"])
    bpy.ops.wm.read_factory_settings(use_empty=True)
    image = bpy.data.images.load(str(empty_path), check_existing=True)
    capsule, mat, tex_node = build_capsule(rects, tex_size, image)
    fbx_path = media / "models_X" / "WorldItems" / "MinidoracatCapsule.fbx"
    fbx_path.parent.mkdir(parents=True, exist_ok=True)
    export_fbx(capsule, str(fbx_path))
    # Side views are human QA only; render them once with the empty atlas.
    set_texture(tex_node, str(empty_path))
    render_side_views(capsule, str(review / "side_neg_y.png"), str(review / "side_pos_y.png"))
    # Previews use the empty/loaded pair; icons cover every atlas with the same mesh/material/camera.
    for loaded, tex_path, stem in ((False, empty_path, "empty"), (True, loaded_path, "loaded")):
        set_texture(tex_node, str(tex_path))
        render_model(capsule, str(review / f"model_{stem}.png"), loaded=loaded)
        render_ground(capsule, str(review / f"ground_{stem}.png"))
    for entry in atlas["icons"]:
        stem = Path(entry["atlas"]).stem
        set_texture(tex_node, entry["atlas"])
        render_icon(capsule, str(out / f"icon_{stem}.png"), entry["loaded"])
        if entry["emit"]:
            set_texture(tex_node, entry["emit"])
            render_icon(capsule, str(out / f"icon_{stem}_emit.png"), entry["loaded"], emissive=True)
    # Re-import must happen after all renders because it resets the factory scene.
    verify_fbx(str(fbx_path), capsule, str(review / "fbx_verify.txt"))
    print("BUILD OK", fbx_path)


if __name__ == "__main__":
    main()
