"""Build Aranea's rigged sculpture and its separate Silk Chamber render stage.

Run: blender -b --factory-startup --python-exit-code 1 --python tools/spider/build.py
     -- [--output DIR] [--render-still] [--render-loop] [--width 1280] [--samples 32]
All geometry is authored here or derived from the repository's canonical SVG.
"""

import argparse
import json
import math
from pathlib import Path
import re
import sys
import xml.etree.ElementTree as ET

import bpy
import bmesh
from mathutils import Vector
from mathutils.geometry import tessellate_polygon

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import validate, validate_preview, validate_gait
from gait import toe_motion, WORLD_SPEED

p = argparse.ArgumentParser()
p.add_argument("--output", type=Path, default=ROOT / "branding/3d")
p.add_argument("--render-still", action="store_true")
p.add_argument("--render-loop", action="store_true")
p.add_argument("--width", type=int, default=1280)
p.add_argument("--samples", type=int, default=32)
p.add_argument("--cuda", action="store_true")
p.add_argument("--frame-step", type=int, choices=(1, 2), default=1)
args = p.parse_args(sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else [])
args.output.mkdir(parents=True, exist_ok=True)
if (
    args.render_loop
    and (args.output / "frames").exists()
    and any((args.output / "frames").iterdir())
):
    p.error("render frames directory must be empty; choose a new --output directory")
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
for col in list(bpy.data.collections):
    if not col.objects:
        bpy.data.collections.remove(col)
character = bpy.data.collections.new("Character")
stage = bpy.data.collections.new("Silk Chamber")
bpy.context.scene.collection.children.link(character)
bpy.context.scene.collection.children.link(stage)


def move_to(obj, col):
    for current in list(obj.users_collection):
        current.objects.unlink(obj)
    col.objects.link(obj)
    return obj


def material(name, color, metal=0, rough=0.35, emission=0):
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Metallic"].default_value = metal
    shader.inputs["Roughness"].default_value = rough
    shader.inputs["Emission Color"].default_value = (*color, 1)
    shader.inputs["Emission Strength"].default_value = emission
    return mat


obsidian = material("Obsidian titanium", (0.018, 0.028, 0.032), 0.72, 0.38)
edge = material("Mint enamel seams", (0.04, 0.65, 0.43), 0.6, 0.25, 0.5)
core = material("Silk reactor", (0.12, 0.95, 0.65), 0.3, 0.22, 3)
nickel = material("Joint nickel", (0.09, 0.13, 0.14), 0.85, 0.28)
slate = material("Chamber basalt", (0.019, 0.026, 0.033), 0.65, 0.32)
silk = material("Spun mint silk", (0.045, 0.24, 0.20), 0.45, 0.4, 0.3)
violet = material("Violet perimeter", (0.18, 0.045, 0.4), 0.3, 0.4, 1.2)


def svg_polygons():
    tree = ET.parse(ROOT / "branding/marks/aranea-glyph.svg")
    path = next(tree.iter("{http://www.w3.org/2000/svg}path")).attrib["d"]
    tokens = re.findall(r"[MLQZ]|-?\d+(?:\.\d+)?", path)
    contours, points, i = [], [], 0
    cursor = Vector((0, 0))
    while i < len(tokens):
        cmd = tokens[i]
        i += 1
        if cmd == "Z":
            contours.append(points)
            points = []
            continue
        dest = Vector((float(tokens[i]), float(tokens[i + 1])))
        i += 2
        if cmd == "M":
            points.append(dest)
            cursor = dest
            continue
        start = cursor.copy()
        if cmd == "Q":
            control = dest
            dest = Vector((float(tokens[i]), float(tokens[i + 1])))
            i += 2
            count = max(
                6, int(((control - start).length + (dest - control).length) / 3)
            )
            for j in range(1, count + 1):
                t = j / count
                points.append(
                    (1 - t) ** 2 * start + 2 * (1 - t) * t * control + t * t * dest
                )
        else:
            count = max(1, math.ceil((dest - start).length / 3))
            points.extend(start.lerp(dest, j / count) for j in range(1, count + 1))
        cursor = dest
    assert len(contours) == 12
    return contours


def xyz(x, y, z):
    return Vector(((x - 160) / 50, (210 - y) / 50, z))


# A high shoulder, raised knee and grounded toe give the original mark depth.
paths_left = [
    [(126, 187, 0.83), (106, 158, 1.22), (108, 126, 0.72), (131, 99, 0.10)],
    [(122, 201, 0.80), (84, 179, 1.16), (77, 154, 0.70), (79, 130, 0.10)],
    [(120, 210, 0.78), (82, 216, 1.10), (65, 234, 0.66), (72, 272, 0.10)],
    [(119, 224, 0.75), (94, 240, 1.12), (97, 266, 0.64), (124, 309, 0.10)],
]
paths, bone_names = [], []
for i, path in enumerate(paths_left):
    for side, sign in [("L", 1), ("R", -1)]:
        paths.append([xyz(x if sign == 1 else 320 - x, y, z) for x, y, z in path])
        bone_names.append(
            [f"leg.{side}{i + 1}.{part}" for part in ("hip", "knee", "tip")]
        )

armature = bpy.data.armatures.new("Aranea skeleton")
rig = bpy.data.objects.new("Aranea.Rig", armature)
character.objects.link(rig)
bpy.context.view_layer.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
root_bone = armature.edit_bones.new("root")
root_bone.head, root_bone.tail = (0, 0, 0), (0, 0, 0.35)
body_bone = armature.edit_bones.new("body")
body_bone.head, body_bone.tail = (0, 0, 0.65), (0, 0.7, 0.65)
body_bone.parent = root_bone
for coords, names in zip(paths, bone_names):
    parent = body_bone
    for j, name in enumerate(names):
        bone = armature.edit_bones.new(name)
        bone.head, bone.tail = coords[j], coords[j + 1]
        bone.parent = parent
        bone.use_connect = j > 0
        parent = bone
bpy.ops.object.mode_set(mode="OBJECT")
rig.show_in_front = True
for bone in rig.pose.bones:
    bone.rotation_mode = "XYZ"
rig["description"] = (
    "Aranea angular brand spider. +Y forward, Z up. Eight 3-bone limbs."
)
rig["source"] = "branding/marks/aranea-glyph.svg"
rig["controls"] = (
    "root: placement; body: body motion; leg.L/R1..4.hip/knee/tip: FK joints"
)


def nearest_segments(point, path):
    results = []
    for j in range(3):
        a, b = path[j], path[j + 1]
        d = Vector((b.x - a.x, b.y - a.y))
        t = max(
            0,
            min(1, (Vector((point.x - a.x, point.y - a.y))).dot(d) / d.length_squared),
        )
        on = a.lerp(b, t)
        dist = (Vector((point.x - on.x, point.y - on.y))).length
        results.append((dist, j, t, on.z))
    return sorted(results)


def skin(obj, leg=None, fixed=None):
    mod = obj.modifiers.new("Aranea armature", "ARMATURE")
    mod.object = rig
    obj.parent = rig
    if fixed or leg is None:
        group = obj.vertex_groups.new(name=fixed or "body")
        group.add(list(range(len(obj.data.vertices))), 1, "REPLACE")
    else:
        groups = [obj.vertex_groups.new(name=n) for n in bone_names[leg]]
        for vertex in obj.data.vertices:
            nearest = nearest_segments(obj.matrix_world @ vertex.co, paths[leg])
            a, b = nearest[:2]
            # Only blend neighboring bones, concentrating the bend near a joint.
            wa, wb = 1 / (a[0] + 0.035) ** 3, 1 / (b[0] + 0.035) ** 3
            groups[a[1]].add([vertex.index], wa / (wa + wb), "REPLACE")
            groups[b[1]].add([vertex.index], wb / (wa + wb), "REPLACE")


def plate(name, outline, level, thickness, leg=None, mat=obsidian, bevel=0.025):
    coords = [xyz(v.x, v.y, level) for v in outline]
    if leg is not None:
        for pt in coords:
            pt.z = nearest_segments(pt, paths[leg])[0][3]
    # Tessellation uses the 2D projection, avoiding non-planar triangulation.
    flat = [Vector((v.x, v.y, 0)) for v in coords]
    tris = tessellate_polygon([flat])
    # Subdivide in the flat plane before lifting the arch: long triangles
    # would otherwise span several joints and fold across the silhouette.
    surface = bpy.data.meshes.new(name + " surface")
    surface.from_pydata([tuple(v) for v in flat], [], [tuple(t) for t in tris])
    bm = bmesh.new()
    bm.from_mesh(surface)
    bmesh.ops.subdivide_edges(bm, edges=list(bm.edges), cuts=2, use_grid_fill=True)
    bmesh.ops.triangulate(bm, faces=list(bm.faces))
    bm.verts.ensure_lookup_table()
    bm.verts.index_update()
    points = [v.co.copy() for v in bm.verts]
    cap_faces = [tuple(v.index for v in f.verts) for f in bm.faces]
    borders = [(e.verts[0].index, e.verts[1].index) for e in bm.edges if e.is_boundary]
    n = len(points)
    for point in points:
        point.z = (
            nearest_segments(point, paths[leg])[0][3] if leg is not None else level
        )
    vertices = [tuple(v - Vector((0, 0, thickness / 2))) for v in points]
    vertices += [tuple(v + Vector((0, 0, thickness / 2))) for v in points]
    faces = [tuple(reversed(f)) for f in cap_faces]
    faces += [tuple(i + n for i in f) for f in cap_faces]
    faces += [(a, b, b + n, a + n) for a, b in borders]
    bm.free()
    bpy.data.meshes.remove(surface)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    for face in mesh.polygons:
        face.use_smooth = len(face.vertices) == 3
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    character.objects.link(obj)
    obj.data.materials.append(mat)
    obj.data.materials.append(edge)
    skin(obj, leg)
    bevel_mod = obj.modifiers.new("Machined mint edge", "BEVEL")
    bevel_mod.width, bevel_mod.segments, bevel_mod.material = bevel, 3, 1
    obj.modifiers.new("Weighted plate normals", "WEIGHTED_NORMAL")
    return obj


def limb_segment(name, start, end, width_a, width_b, depth, bone, mat=obsidian):
    direction = (end - start).normalized()
    side = Vector((-direction.y, direction.x, 0)).normalized()
    up = direction.cross(side).normalized()
    vertices = []
    cross_section = [
        (-0.7, 0.5),
        (0.7, 0.5),
        (1, 0.25),
        (1, -0.25),
        (0.7, -0.5),
        (-0.7, -0.5),
        (-1, -0.25),
        (-1, 0.25),
    ]
    for point, width in ((start, width_a), (end, width_b)):
        vertices.extend(
            tuple(point + side * x * width * 0.5 + up * z * depth)
            for x, z in cross_section
        )
    faces = [tuple(reversed(range(8))), tuple(range(8, 16))]
    faces += [(i, (i + 1) % 8, (i + 1) % 8 + 8, i + 8) for i in range(8)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    character.objects.link(obj)
    obj.data.materials.append(mat)
    skin(obj, fixed=bone)
    bevel = obj.modifiers.new("Machined bevel", "BEVEL")
    bevel.width, bevel.segments = 0.018, 3
    obj.modifiers.new("Hard surface normals", "WEIGHTED_NORMAL")
    return obj


contours = svg_polygons()
for i, path in enumerate(paths):
    for j in range(3):
        start, end = path[j].lerp(path[j + 1], 0.045), path[j].lerp(path[j + 1], 0.955)
        widths = [(0.22, 0.24), (0.24, 0.15), (0.15, 0.018)]
        limb_segment(
            "Limb." + bone_names[i][j], start, end, *widths[j], 0.16, bone_names[i][j]
        )
        # A recessed luminous spine follows each mechanical blade.
        direction = (end - start).normalized()
        side = Vector((-direction.y, direction.x, 0)).normalized()
        up = direction.cross(side).normalized()
        limb_segment(
            "Seam." + bone_names[i][j],
            start + up * 0.083,
            end + up * 0.083,
            0.025,
            0.012,
            0.007,
            bone_names[i][j],
            edge,
        )
plate("Carapace.L", contours[8], 0.91, 0.32, bevel=0.045)
plate("Carapace.R", contours[9], 0.91, 0.32, bevel=0.045)
plate("Core", contours[10], 1.13, 0.16, mat=core, bevel=0.025)
plate("Abdomen shield", contours[11], 0.76, 0.4, bevel=0.065)
# Inset shield follows the real brand shape rather than adding a new symbol.
shield_center = Vector((160, 250))
inset = [shield_center + (v - shield_center) * 0.70 for v in contours[11]]
plate("Abdomen inlay", inset, 0.98, 0.025, mat=nickel, bevel=0.018)


def sphere(name, pos, radius, mat, leg=None, bone=None):
    bpy.ops.mesh.primitive_uv_sphere_add(
        segments=16, ring_count=8, radius=radius, location=pos
    )
    obj = move_to(bpy.context.object, character)
    obj.name = name
    obj.data.materials.append(mat)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    skin(obj, leg, bone)
    for poly in obj.data.polygons:
        poly.use_smooth = True
    return obj


for i, path in enumerate(paths):
    for j in (0, 1, 2):
        sphere(
            "Joint." + bone_names[i][j],
            path[j],
            0.10 if j else 0.12,
            obsidian,
            bone=bone_names[i][j],
        )
# Structural underbody joins the independent armor plates.
bpy.ops.mesh.primitive_uv_sphere_add(
    segments=32, ring_count=16, location=(0, -0.1, 0.64)
)
body = move_to(bpy.context.object, character)
body.name = "Internal thorax"
body.scale = (0.59, 1.03, 0.24)
body.data.materials.append(obsidian)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
skin(body)


# Bake hard-surface modifiers before skinning is exported. Bevel can generate
# vertices without groups (notably on the tiny reactor). Every rigid plate has
# exactly one bone, so restore that influence for all evaluated vertices.
armature.pose_position = "REST"
for obj in list(character.objects):
    if obj.type != "MESH":
        continue
    bpy.context.view_layer.objects.active = obj
    for modifier in list(obj.modifiers):
        if modifier.type != "ARMATURE":
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    assert len(obj.vertex_groups) == 1, obj.name
    obj.vertex_groups[0].add(list(range(len(obj.data.vertices))), 1, "REPLACE")
armature.pose_position = "POSE"


def animate(name, length, walking=False):
    rig.animation_data_create()
    action = bpy.data.actions.new(name)
    rig.animation_data.action = action
    for frame in range(1, length + 1):
        bpy.context.scene.frame_set(frame)
        phase = 2 * math.pi * (frame - 1) / (length - 1)
        for bone in rig.pose.bones:
            bone.rotation_euler = (0, 0, 0)
            bone.location = (0, 0, 0)
        body_pose = rig.pose.bones["body"]
        body_pose.location.z = (0.012 if walking else 0.012) * math.sin(
            phase * 2 if walking else phase
        )
        body_pose.rotation_euler.x = 0.004 * math.sin(phase)
        for i, names in enumerate(bone_names):
            sign = 1 if i % 2 == 0 else -1
            # Alternating tetrapod groups, L1/R2/L3/R4 against the other four.
            wave = phase + (math.pi if ((i // 2 + i % 2) % 2) else 0)
            lift = (1 - math.cos(wave)) * 0.5
            hip = rig.pose.bones[names[0]]
            knee = rig.pose.bones[names[1]]
            tip = rig.pose.bones[names[2]]
            if walking:
                # Solve the two distal segments analytically. Each planted toe
                # stays above the dais, with an alternating lifted swing phase.
                inward = paths[i][1] - paths[i][3]
                inward.z = 0
                offset = (0.5 if ((i // 2 + i % 2) % 2) else 0) + (i // 2) * 0.035
                forward, height = toe_motion((frame - 1) / (length - 1) + offset)
                bpy.context.view_layer.update()
                # The proximal joint follows the foot sweep instead of waving
                # on an unrelated sine. Distal IK keeps the contact planted.
                origin = hip.head.copy()
                rest = hip.bone
                direction = (
                    paths[i][1]
                    - paths[i][0]
                    + Vector((0, forward * 0.3, height * 0.08))
                )
                rotation = (rest.tail_local - rest.head_local).rotation_difference(
                    direction
                )
                matrix = rotation.to_matrix().to_4x4() @ rest.matrix_local
                matrix.translation = origin
                hip.matrix = matrix
                bpy.context.view_layer.update()
                start = knee.head.copy()
                foot = (
                    paths[i][3]
                    + inward.normalized() * 0.38
                    + Vector((0, forward, height))
                )
                delta = foot - start
                distance = delta.length
                axis = delta.normalized()
                l1, l2 = (
                    (paths[i][2] - paths[i][1]).length,
                    (paths[i][3] - paths[i][2]).length,
                )
                assert abs(l1 - l2) < distance < l1 + l2, (
                    f"Walk target outside limb reach: {i} {frame} {distance} {l1 + l2}"
                )
                along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
                bend = paths[i][2] - paths[i][1]
                bend = (bend - axis * bend.dot(axis)).normalized()
                joint = (
                    start
                    + axis * along
                    + bend * math.sqrt(max(0, l1 * l1 - along * along))
                )
                for pose, origin, destination in (
                    (knee, start, joint),
                    (tip, joint, foot),
                ):
                    rest = pose.bone
                    rotation = (rest.tail_local - rest.head_local).rotation_difference(
                        destination - origin
                    )
                    matrix = rotation.to_matrix().to_4x4() @ rest.matrix_local
                    matrix.translation = origin
                    pose.matrix = matrix
                    bpy.context.view_layer.update()
            else:
                hip.rotation_euler.z = sign * 0.012 * math.sin(wave)
                hip.rotation_euler.x = 0.008 * math.sin(wave)
                knee.rotation_euler.x = -0.009 * lift
                tip.rotation_euler.x = 0.008 * lift
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
    # Set linear interpolation so baked transforms match the procedural curve.
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = "LINEAR"
    action.use_fake_user = True
    return action


idle = animate("Idle", 97)
walk = animate("Walk", 49, True)
validate(rig)
validate_gait(rig)
rig.animation_data.action = idle
for action in (idle, walk):
    track = rig.animation_data.nla_tracks.new()
    track.name = action.name
    strip = track.strips.new(action.name, 1, action)
    track.mute = True
bpy.context.scene.frame_set(1)
# Export only the character; stage lights and cameras are not reusable geometry.
bpy.ops.object.select_all(action="DESELECT")
for obj in character.objects:
    obj.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.export_scene.gltf(
    filepath=str(args.output / "aranea-spider.glb"),
    export_format="GLB",
    use_selection=True,
    export_animations=True,
    export_animation_mode="ACTIONS",
    export_skins=True,
    export_apply=False,
    export_materials="EXPORT",
    export_force_sampling=True,
    export_frame_range=False,
)


# Independent scene: concentric black stone, suspended silk and a violet rim.
def cylinder(name, radius, depth, z, mat):
    bpy.ops.mesh.primitive_cylinder_add(
        vertices=128, radius=radius, depth=depth, location=(0, 0, z)
    )
    obj = move_to(bpy.context.object, stage)
    obj.name = name
    obj.data.materials.append(mat)
    bevel = obj.modifiers.new("Soft stone edges", "BEVEL")
    bevel.width, bevel.segments = 0.035, 3
    obj.modifiers.new("Stone normals", "WEIGHTED_NORMAL")
    return obj


def thread(name, points, radius, mat):
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = 2
    spline = curve.splines.new("POLY")
    spline.points.add(len(points) - 1)
    for point, xyzv in zip(spline.points, points):
        point.co = (*xyzv, 1)
    obj = bpy.data.objects.new(name, curve)
    stage.objects.link(obj)
    obj.data.materials.append(mat)
    return obj


cylinder("Basalt dais", 3.30, 0.24, -0.19, slate)
cylinder("Dark horizon", 200, 0.15, -0.40, slate)
for radius in (2.65, 2.76, 3.12):
    thread(
        "Engraved circuit",
        [
            (
                radius * math.cos(t * math.tau / 256),
                radius * math.sin(t * math.tau / 256),
                -0.058,
            )
            for t in range(257)
        ],
        0.007,
        silk,
    )
thread(
    "Violet rim",
    [
        (
            3.25 * math.cos(t * math.tau / 256),
            3.25 * math.sin(t * math.tau / 256),
            -0.08,
        )
        for t in range(257)
    ],
    0.012,
    violet,
)
# A quiet radial silk lattice behind the character, with deliberately sagging strands.
for i in range(16):
    theta = i * math.tau / 16
    thread(
        "Radial silk",
        [(r * math.cos(theta), r * math.sin(theta), -0.055) for r in (2.8, 3.3, 4.3)],
        0.0035,
        silk,
    )
for radius in (3.55, 4.15):
    points = []
    for i in range(16):
        a, b = (
            Vector(
                (
                    radius * math.cos(i * math.tau / 16),
                    radius * math.sin(i * math.tau / 16),
                    0.0,
                )
            ),
            Vector(
                (
                    radius * math.cos((i + 1) * math.tau / 16),
                    radius * math.sin((i + 1) * math.tau / 16),
                    0.0,
                )
            ),
        )
        for j in range(9):
            t = j / 8
            pt = a.lerp(b, t)
            pt.z = -0.05 - 0.07 * math.sin(t * math.pi)
            points.append(pt)
    points.append(points[0])
    thread("Spun perimeter", points, 0.004, silk)


def aim(obj, point):
    obj.rotation_euler = (
        (Vector(point) - obj.location).to_track_quat("-Z", "Y").to_euler()
    )


def area(name, position, color, energy, size, target=(0, 0, 0)):
    data = bpy.data.lights.new(name, "AREA")
    data.energy, data.color, data.shape, data.size = energy, color, "DISK", size
    obj = bpy.data.objects.new(name, data)
    stage.objects.link(obj)
    obj.location = position
    aim(obj, target)
    return obj


area("Soft silver key", (1, 1, 6), (0.72, 0.86, 1), 650, 5)
area("Mint rim", (-4, 1, 3), (0.16, 1, 0.67), 700, 4)
area("Violet fill", (3, -2, 2.5), (0.46, 0.22, 1), 500, 3)
area("Front softbox", (0, -5, 4), (0.7, 0.88, 0.96), 250, 4)
camera_data = bpy.data.cameras.new("Portrait camera")
camera = bpy.data.objects.new("Portrait camera", camera_data)
stage.objects.link(camera)
camera.location = (3.5, -6.8, 8.6)
aim(camera, (0, 0, 0.20))
camera_data.type = "ORTHO"
camera_data.ortho_scale = 10.7
scene = bpy.context.scene
scene.camera = camera
scene.world.color = (0.025, 0.025, 0.025)
scene.render.engine = "CYCLES"
scene.cycles.samples = args.samples
scene.cycles.use_denoising = True
if args.cuda:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "CUDA"
    prefs.get_devices()
    assert any(d.type == "CUDA" for d in prefs.devices), "No CUDA device found"
    for device in prefs.devices:
        device.use = device.type == "CUDA"
    scene.cycles.device = "GPU"
scene.render.resolution_x, scene.render.resolution_y = (
    args.width,
    round(args.width * 9 / 16),
)
scene.render.resolution_percentage = 100
scene.render.fps = 24
scene.frame_start, scene.frame_end = 1, 48
scene.frame_step = args.frame_step
scene.view_settings.view_transform = "AgX"
scene.render.image_settings.file_format = "PNG"
scene.render.film_transparent = False
# The camera and walking rig share a two-second loop, ending at frame 49.
for frame in range(1, 50, 2):
    phase = (frame - 1) / 48 * math.tau
    camera.location = (
        3.5 + 0.24 * math.sin(phase),
        -6.8 + 0.14 * (1 - math.cos(phase)),
        8.6,
    )
    aim(camera, (0, 0, 0.20))
    camera.keyframe_insert("location", frame=frame)
    camera.keyframe_insert("rotation_euler", frame=frame)
rig.animation_data.action = walk
scene["preview_action"] = "Walk"
scene.frame_set(1)
validate_preview(scene, rig)
# Helpful opening view and controls in the editable file.
for screen in bpy.data.screens:
    for area_ui in screen.areas:
        if area_ui.type == "VIEW_3D":
            area_ui.spaces.active.region_3d.view_perspective = "CAMERA"
bpy.ops.object.select_all(action="DESELECT")
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.context.preferences.filepaths.save_version = 0
bpy.ops.wm.save_as_mainfile(filepath=str(args.output / "aranea-spider.blend"))
report = {
    "source": "branding/marks/aranea-glyph.svg",
    "legs": 8,
    "bones": 26,
    "clips": {"Idle": {"frames": 97, "fps": 24}, "Walk": {"frames": 49, "fps": 24}},
    "blender": bpy.app.version_string,
    "scene": "Silk Chamber",
    "preview_action": "Walk",
    "walk_world_speed": WORLD_SPEED,
    "render_frames": len(range(1, 49, args.frame_step)),
    "render_fps": 24 / args.frame_step,
}
(args.output / "model-info.json").write_text(json.dumps(report, indent=2) + "\n")
if args.render_still:
    scene.render.filepath = str(args.output / "silk-chamber.png")
    bpy.ops.render.render(write_still=True)
if args.render_loop:
    (args.output / "frames").mkdir(exist_ok=True)
    scene.render.filepath = str(args.output / "frames/frame-")
    bpy.ops.render.render(animation=True)
print("SPIDER_BUILD_COMPLETE", args.output)
