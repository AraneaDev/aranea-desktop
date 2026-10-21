"""Reopen the saved Blender file, then independently import and inspect the GLB.

blender -b --factory-startup --python-exit-code 1 --python tools/spider/check-export.py
"""

import json
from pathlib import Path
import struct
import sys
import bpy

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from validate import validate, validate_preview, validate_gait

out = ROOT / "branding/3d"
bpy.ops.wm.open_mainfile(filepath=str(out / "aranea-spider.blend"))
validate_preview(bpy.context.scene, bpy.data.objects["Aranea.Rig"])
validate(bpy.data.objects["Aranea.Rig"])
validate_gait(bpy.data.objects["Aranea.Rig"])
with (out / "aranea-spider.glb").open("rb") as handle:
    magic, version, length = struct.unpack("<4sII", handle.read(12))
    assert magic == b"glTF" and version == 2
    assert length == (out / "aranea-spider.glb").stat().st_size
    size, kind = struct.unpack("<II", handle.read(8))
    assert kind == 0x4E4F534A
    doc = json.loads(handle.read(size))
assert len(doc["skins"]) == 1 and len(doc["skins"][0]["joints"]) == 26
assert {a["name"] for a in doc["animations"]} == {"Idle", "Walk"}
assert all(
    "JOINTS_0" in prim["attributes"] and "WEIGHTS_0" in prim["attributes"]
    for mesh in doc["meshes"]
    for prim in mesh["primitives"]
)
assert all(
    not image.get("uri", "").startswith(("http:", "https:"))
    for image in doc.get("images", [])
)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.gltf(filepath=str(out / "aranea-spider.glb"))
rig = next(o for o in bpy.context.scene.objects if o.type == "ARMATURE")
assert len(rig.data.bones) == 26
assert sum(o.type == "MESH" for o in bpy.context.scene.objects) >= 12
print("SPIDER_EXPORT_VERIFIED: saved Blender rig and independent GLB round-trip")
