"""ひより 3D モデル生成スクリプト (トゥーン調ローポリ)

使い方:
  /Applications/Blender.app/Contents/MacOS/Blender -b -P tools/blender/build_hiyori.py -- <出力ディレクトリ>

出力: hiyori.glb / hiyori.blend / preview_front.png / preview_side.png / preview_three.png
キャラクターは -Y 方向 (Blender のフロントビュー手前) を向く。単位はメートル、身長およそ 1.58m。
"""
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector

out_dir = sys.argv[sys.argv.index("--") + 1] if "--" in sys.argv else "/tmp/hiyori"
os.makedirs(out_dir, exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene


# ---------- マテリアル ----------
def mat(name, rgb, rough=0.9):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nodes = m.node_tree.nodes
    b = nodes.get("Principled BSDF")
    if b is None:
        nodes.clear()
        b = nodes.new("ShaderNodeBsdfPrincipled")
        out = nodes.new("ShaderNodeOutputMaterial")
        m.node_tree.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    return m


M = {
    "skin": mat("skin", (1.0, 0.82, 0.72)),
    "hair": mat("hair", (0.62, 0.52, 0.42), 0.5),
    "cardigan": mat("cardigan", (0.98, 0.93, 0.74)),
    "blouse": mat("blouse", (0.98, 0.97, 0.96)),
    "skirt": mat("skirt", (0.84, 0.74, 0.60)),
    "shoe": mat("shoe", (0.62, 0.55, 0.45)),
    "eye": mat("eye", (0.38, 0.24, 0.14), 0.3),
    "white": mat("white", (1, 1, 1), 0.3),
    "pink": mat("pink", (0.95, 0.55, 0.62)),
    "ribbon": mat("ribbon", (0.72, 0.64, 0.50)),
    "blush": mat("blush", (1.0, 0.55, 0.55)),
    "line": mat("line", (0.12, 0.07, 0.05)),
}
M["line"].use_backface_culling = True


def finish(o, mname, smooth=True, outline=0.0):
    o.data.materials.clear()
    o.data.materials.append(M[mname])
    if smooth:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.shade_smooth()
        o.select_set(False)
    return o


def sphere(name, loc, scale, mname, seg=32, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=seg // 2, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    o.rotation_euler = rot
    bpy.ops.object.transform_apply(scale=True, rotation=True)
    return finish(o, mname)


def limb(name, p1, p2, r1, r2, mname, seg=20):
    """p1 から p2 へ向かう先細りの筒。"""
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    bpy.ops.mesh.primitive_cone_add(vertices=seg, radius1=r1, radius2=r2, depth=d.length,
                                    location=(p1 + p2) / 2)
    o = bpy.context.object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(d.normalized())
    bpy.ops.object.transform_apply(rotation=True)
    return finish(o, mname)


def add_outline(o, width=0.0035):
    """裏返しの殻でアウトラインを付ける。"""
    mod = o.modifiers.new("outline", "SOLIDIFY")
    mod.thickness = -width
    mod.offset = 1
    mod.use_flip_normals = True
    mod.material_offset = len(o.data.materials)
    o.data.materials.append(M["line"])


# ---------- 寸法 ----------
HEAD_Z = 1.43
FRONT = -1  # 顔の向き (-Y)

# ---------- 頭・顔 ----------
head = sphere("head", (0, 0, HEAD_Z), (0.085, 0.088, 0.098), "skin", seg=48)
# あご先を少し細く
bm = bmesh.new()
bm.from_mesh(head.data)
for v in bm.verts:
    if v.co.z < -0.02:
        t = (-0.02 - v.co.z) / 0.08
        v.co.x *= 1 - 0.28 * t
        v.co.y *= 1 - 0.18 * t
bm.to_mesh(head.data)
bm.free()

neck = limb("neck", (0, 0.003, 1.33), (0, 0.003, 1.40), 0.032, 0.030, "skin")

# 目 (薄い楕円 + ハイライト)
for s in (-1, 1):
    x = s * 0.037
    y = -0.081
    z = HEAD_Z - 0.006
    eye = sphere(f"eye{s}", (x, y, z), (0.020, 0.006, 0.026), "eye", seg=24)
    sphere(f"eye_hl{s}", (x - s * 0.006, y - 0.004, z + 0.010), (0.0065, 0.003, 0.0075), "white", seg=12)
    sphere(f"blush{s}", (s * 0.056, -0.070, HEAD_Z - 0.036), (0.020, 0.005, 0.011), "blush", seg=16)
    # まつげ・眉
    limb(f"lash{s}", (x - s * 0.022, y - 0.003, z + 0.024), (x + s * 0.022, y - 0.003, z + 0.026),
         0.0025, 0.0025, "line", seg=8)
    limb(f"brow{s}", (x - s * 0.018, -0.080, z + 0.042), (x + s * 0.016, -0.080, z + 0.046),
         0.0018, 0.0014, "hair", seg=8)
    # ピアス
    sphere(f"ear{s}", (s * 0.086, 0.0, HEAD_Z - 0.030), (0.008, 0.008, 0.008), "white", seg=12)
# 口
limb("mouth", (-0.010, -0.083, HEAD_Z - 0.052), (0.010, -0.083, HEAD_Z - 0.052), 0.0022, 0.0022, "pink", seg=8)
# 鼻
sphere("nose", (0, -0.087, HEAD_Z - 0.030), (0.004, 0.003, 0.004), "skin", seg=8)

# ---------- 髪 ----------
hair_cap = sphere("hair_cap", (0, 0.006, HEAD_Z + 0.008), (0.093, 0.094, 0.098), "hair", seg=48)
# 顔の前面側を切り抜く (前髪の下から顔を出す)
bm = bmesh.new()
bm.from_mesh(hair_cap.data)
for v in bm.verts:
    # 前方・下側の頂点を後ろへ引いて顔を露出
    if v.co.y < -0.02 and v.co.z < 0.030:
        v.co.y = max(v.co.y * 0.0 + 0.012, v.co.y + 0.0)
        v.co.y = -0.012 + (v.co.y + 0.012) * 0.2
bm.to_mesh(hair_cap.data)
bm.free()
# 前髪 (薄い扇形のかたまりを並べる)
for i, x in enumerate((-0.060, -0.030, 0.0, 0.030, 0.060)):
    zr = 0.040 - abs(x) * 0.25
    sphere(f"bang{i}", (x, -0.074 + abs(x) * 0.25, HEAD_Z + 0.050 - abs(x) * 0.2),
           (0.027, 0.017, zr), "hair", seg=16, rot=(0, math.radians(-x * 300), 0))
# 横髪
for s in (-1, 1):
    sphere(f"side_hair{s}", (s * 0.082, -0.020, HEAD_Z - 0.015), (0.014, 0.030, 0.062), "hair", seg=16)
# サイドポニー (右側 = 画面の右、+X)
bpy.ops.mesh.primitive_uv_sphere_add(location=(0.075, 0.040, HEAD_Z + 0.040))
bpy.context.object.name = "_tmp"
bpy.data.objects.remove(bpy.context.object)
pts = [(0.078, 0.040, HEAD_Z + 0.040, 0.020),
       (0.098, 0.050, HEAD_Z + 0.000, 0.026),
       (0.112, 0.060, HEAD_Z - 0.060, 0.030),
       (0.118, 0.065, HEAD_Z - 0.130, 0.028),
       (0.115, 0.062, HEAD_Z - 0.200, 0.020),
       (0.110, 0.058, HEAD_Z - 0.250, 0.008)]
for i, (x, y, z, r) in enumerate(pts):
    sphere(f"pony{i}", (x, y, z), (r, r * 0.9, r * 1.6), "hair", seg=16)
sphere("ribbon", (0.080, 0.036, HEAD_Z + 0.040), (0.016, 0.012, 0.022), "ribbon", seg=12)

# ---------- 体 ----------
# ブラウス (胸〜腰)
blouse = limb("blouse", (0, 0, 1.00), (0, 0, 1.33), 0.088, 0.066, "blouse", seg=32)
blouse.scale = (1.0, 0.72, 1.0)
bpy.context.view_layer.objects.active = blouse
bpy.ops.object.transform_apply(scale=True)
# 襟 (丸襟)
collar = limb("collar", (0, 0.000, 1.315), (0, 0.000, 1.350), 0.058, 0.040, "white", seg=32)
collar.scale = (1, 0.9, 1)
bpy.context.view_layer.objects.active = collar
bpy.ops.object.transform_apply(scale=True)
# リボン
sphere("neck_ribbon", (0, -0.066, 1.305), (0.018, 0.010, 0.012), "ribbon", seg=12)
limb("ribbon_tail1", (0, -0.068, 1.298), (-0.010, -0.070, 1.230), 0.006, 0.004, "ribbon", seg=8)
limb("ribbon_tail2", (0, -0.068, 1.298), (0.010, -0.070, 1.236), 0.006, 0.004, "ribbon", seg=8)

# カーディガン (前が開いた殻: 円筒の前面中央を削除)
cardi = limb("cardigan", (0, 0, 0.94), (0, 0, 1.30), 0.100, 0.082, "cardigan", seg=32)
cardi.scale = (1.0, 0.76, 1.0)
bpy.context.view_layer.objects.active = cardi
bpy.ops.object.transform_apply(scale=True)
bm = bmesh.new()
bm.from_mesh(cardi.data)
bmesh.ops.delete(bm, geom=[f for f in bm.faces
                           if f.calc_center_median().y < -0.045 and abs(f.calc_center_median().x) < 0.028
                           and len(f.verts) == 4], context="FACES")
bm.to_mesh(cardi.data)
bm.free()
cardi.modifiers.new("solid", "SOLIDIFY").thickness = 0.006
for z in (1.20, 1.12, 1.04):
    sphere(f"button{z}", (0.0, -0.077, z), (0.006, 0.003, 0.006), "skirt", seg=8)

# スカート (プリーツ入りのロングスカート)
bpy.ops.mesh.primitive_cone_add(vertices=48, radius1=0.240, radius2=0.098, depth=0.62,
                                location=(0, 0.004, 0.70), end_fill_type="NOTHING")
skirt = bpy.context.object
skirt.name = "skirt"
skirt.scale = (1.0, 0.82, 1.0)
bpy.ops.object.transform_apply(scale=True)
bm = bmesh.new()
bm.from_mesh(skirt.data)
for v in bm.verts:
    ang = math.atan2(v.co.y, v.co.x)
    k = 1 + 0.045 * math.cos(ang * 24)  # 24 本のプリーツ
    v.co.x *= k
    v.co.y *= k
bm.to_mesh(skirt.data)
bm.free()
skirt.modifiers.new("solid", "SOLIDIFY").thickness = 0.006
finish(skirt, "skirt", smooth=False)
bpy.context.view_layer.objects.active = skirt
bpy.ops.object.shade_smooth()
# ウエストバンド
band = limb("waist", (0, 0.004, 0.985), (0, 0.004, 1.015), 0.100, 0.100, "skirt", seg=32)
band.scale = (1, 0.82, 1)
bpy.context.view_layer.objects.active = band
bpy.ops.object.transform_apply(scale=True)

# ---------- 脚・靴 ----------
for s in (-1, 1):
    x = s * 0.050
    limb(f"leg{s}", (x, 0.0, 0.040), (x, 0.0, 0.50), 0.030, 0.040, "skin")
    shoe = sphere(f"shoe{s}", (x, -0.030, 0.035), (0.035, 0.080, 0.035), "shoe", seg=20)
    sphere(f"heel{s}", (x, 0.030, 0.025), (0.020, 0.020, 0.035), "shoe", seg=12)

# ---------- 腕 ----------
# 画面右 (+X) = 脚の横に垂らす腕
sh_r = Vector((0.108, 0.0, 1.265))
el_r = Vector((0.140, 0.010, 1.065))
wr_r = Vector((0.138, -0.010, 0.900))
sphere("shoulder_r", sh_r, (0.040, 0.040, 0.040), "cardigan", seg=16)
limb("upper_arm_r", sh_r, el_r, 0.040, 0.037, "cardigan")
limb("fore_arm_r", el_r, wr_r, 0.037, 0.034, "cardigan")
sphere("elbow_r", el_r, (0.037, 0.037, 0.037), "cardigan", seg=16)
sphere("hand_r", wr_r + Vector((0, 0, -0.045)), (0.027, 0.020, 0.045), "skin", seg=16)

# 画面左 (-X) = 肘を曲げて社員証を持つ腕
sh_l = Vector((-0.108, 0.0, 1.265))
el_l = Vector((-0.150, -0.020, 1.085))
wr_l = Vector((-0.105, -0.090, 1.245))
sphere("shoulder_l", sh_l, (0.040, 0.040, 0.040), "cardigan", seg=16)
limb("upper_arm_l", sh_l, el_l, 0.040, 0.037, "cardigan")
limb("fore_arm_l", el_l, wr_l, 0.037, 0.034, "cardigan")
sphere("elbow_l", el_l, (0.037, 0.037, 0.037), "cardigan", seg=16)
sphere("hand_l", wr_l + Vector((0.008, -0.020, 0.030)), (0.028, 0.026, 0.034), "skin", seg=16)

# ---------- 社員証とストラップ ----------
card = bpy.ops.mesh.primitive_cube_add(location=(-0.095, -0.125, 1.275))
card = bpy.context.object
card.name = "id_card"
card.scale = (0.045, 0.004, 0.030)
card.rotation_euler = (0, math.radians(-12), math.radians(-18))
bpy.ops.object.transform_apply(scale=True, rotation=True)
finish(card, "white", smooth=False)
stripe = bpy.ops.mesh.primitive_cube_add(location=(-0.094, -0.1285, 1.292))
stripe = bpy.context.object
stripe.scale = (0.043, 0.0015, 0.007)
stripe.rotation_euler = (0, math.radians(-12), math.radians(-18))
bpy.ops.object.transform_apply(scale=True, rotation=True)
finish(stripe, "pink", smooth=False)
# ストラップ: 首の後ろから胸前を通りカードへ
strap = [(-0.040, 0.020, 1.360), (-0.052, -0.060, 1.330), (-0.056, -0.085, 1.300), (-0.085, -0.112, 1.290)]
for a, b in zip(strap, strap[1:]):
    limb("strap", a, b, 0.0035, 0.0035, "pink", seg=6)
strap2 = [(0.040, 0.020, 1.360), (0.052, -0.060, 1.330), (0.040, -0.088, 1.240), (0.0, -0.092, 1.205),
          (-0.050, -0.100, 1.230), (-0.085, -0.115, 1.265)]
for a, b in zip(strap2, strap2[1:]):
    limb("strap", a, b, 0.0035, 0.0035, "pink", seg=6)

# ---------- アウトライン ----------
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name.split(".")[0] not in (
            "lash", "brow", "mouth", "id_card", "strap", "eye_hl", "button"):
        w = 0.0025 if o.name.startswith(("eye", "blush", "ear", "nose", "ribbon")) else 0.0035
        if o.name.startswith(("lash", "brow", "mouth", "strap", "eye_hl", "blush")):
            continue
        add_outline(o, w)

# ---------- 整理: 親オブジェクトにまとめる ----------
root = bpy.data.objects.new("Hiyori", None)
scene.collection.objects.link(root)
for o in list(bpy.data.objects):
    if o is not root and o.parent is None:
        o.parent = root

# ---------- レンダリング用ライト・カメラ ----------
scene.render.engine = "BLENDER_EEVEE"
scene.render.resolution_x = 900
scene.render.resolution_y = 1300
scene.render.film_transparent = False
scene.world = bpy.data.worlds.new("w")
scene.world.use_nodes = True
wn = scene.world.node_tree.nodes
bg = wn.get("Background")
if bg is None:
    wn.clear()
    bg = wn.new("ShaderNodeBackground")
    wo = wn.new("ShaderNodeOutputWorld")
    scene.world.node_tree.links.new(bg.outputs["Background"], wo.inputs["Surface"])
bg.inputs[0].default_value = (0.95, 0.95, 0.97, 1)
bg.inputs[1].default_value = 0.55
scene.view_settings.view_transform = "Standard"

bpy.ops.object.light_add(type="SUN", location=(-2, -3, 4))
sun = bpy.context.object
sun.data.energy = 1.1
sun.rotation_euler = (math.radians(50), 0, math.radians(-25))
bpy.ops.object.light_add(type="SUN", location=(3, -2, 2))
fill = bpy.context.object
fill.data.energy = 0.35
fill.rotation_euler = (math.radians(70), 0, math.radians(40))

bpy.ops.object.camera_add()
cam = bpy.context.object
scene.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = 1.85


def shot(name, loc, rot, ortho=1.85, center_z=0.79):
    cam.data.ortho_scale = ortho
    cam.location = loc
    cam.rotation_euler = rot
    scene.render.filepath = os.path.join(out_dir, name)
    bpy.ops.render.render(write_still=True)


shot("preview_front.png", (0, -6, 0.79), (math.radians(90), 0, 0))
shot("preview_side.png", (6, 0, 0.79), (math.radians(90), 0, math.radians(90)))
shot("preview_three.png", (-3.2, -4.4, 1.0), (math.radians(86), 0, math.radians(-36)))
shot("preview_face.png", (0, -6, 1.40), (math.radians(90), 0, 0), ortho=0.45)

# ---------- 書き出し ----------
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out_dir, "hiyori.blend"))
for o in bpy.data.objects:
    o.select_set(o.type == "MESH" or o is root)
bpy.ops.export_scene.gltf(filepath=os.path.join(out_dir, "hiyori.glb"), export_format="GLB",
                          use_selection=True)
print("done:", out_dir)
