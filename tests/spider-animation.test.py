"""Exercise authoring helpers in Blender, without building or exporting artwork.

Run with Blender --background --factory-startup --python-exit-code 1 --python
 tests/spider-animation.test.py
"""

import sys
import unittest
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools/spider"))
from animation import bake_clip, pose_walk_leg, set_linear_interpolation


class AnimationTests(unittest.TestCase):
    def setUp(self):
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.object.delete(use_global=False)
        for action in list(bpy.data.actions):
            bpy.data.actions.remove(action)
        self.path = [
            Vector(point)
            for point in [
                (-0.68, 0.46, 0.83),
                (-1.08, 1.04, 1.22),
                (-1.04, 1.68, 0.72),
                (-0.58, 2.22, 0.10),
            ]
        ]
        self.names = ["leg.L1.hip", "leg.L1.knee", "leg.L1.tip"]
        armature = bpy.data.armatures.new("Test skeleton")
        self.rig = bpy.data.objects.new("Test rig", armature)
        bpy.context.scene.collection.objects.link(self.rig)
        bpy.context.view_layer.objects.active = self.rig
        self.rig.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        root = armature.edit_bones.new("root")
        root.head, root.tail = (0, 0, 0), (0, 0, 0.35)
        body = armature.edit_bones.new("body")
        body.head, body.tail = (0, 0, 0.65), (0, 0.7, 0.65)
        body.parent = root
        parent = body
        for index, name in enumerate(self.names):
            bone = armature.edit_bones.new(name)
            bone.head, bone.tail = self.path[index : index + 2]
            bone.parent = parent
            bone.use_connect = index > 0
            parent = bone
        bpy.ops.object.mode_set(mode="OBJECT")
        for bone in self.rig.pose.bones:
            bone.rotation_mode = "XYZ"

    def test_walk_pose_plants_and_pushes_toe_then_lifts_for_swing(self):
        points = []
        for frame in (1, 9, 17, 39, 49):
            for bone in self.rig.pose.bones:
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
            pose_walk_leg(self.rig, self.path, self.names, 0, frame, 49)
            points.append(self.rig.pose.bones[self.names[-1]].tail.copy())
        for point in points[:3]:
            self.assertAlmostEqual(point.z, 0.1, places=5)
        self.assertAlmostEqual(points[1].y - points[0].y, -0.1128205128, places=5)
        self.assertAlmostEqual(points[2].y - points[1].y, -0.1128205128, places=5)
        self.assertGreater(points[3].z, 0.24)
        self.assertLess((points[0] - points[4]).length, 1e-5)

    def test_walk_phase_staggers_the_other_group_and_later_leg_pairs(self):
        points = []
        for index in (0, 1, 2):
            for bone in self.rig.pose.bones:
                bone.rotation_euler = (0, 0, 0)
                bone.location = (0, 0, 0)
            pose_walk_leg(self.rig, self.path, self.names, index, 1, 49)
            points.append(self.rig.pose.bones[self.names[-1]].tail.copy())
        for point in points:
            self.assertAlmostEqual(point.z, 0.1, places=5)
        self.assertAlmostEqual(points[1].y - points[0].y, -0.3384615385, places=5)
        self.assertAlmostEqual(points[2].y - points[1].y, -0.0236923077, places=5)

    def test_idle_bake_resets_bones_and_preserves_loop_motion(self):
        self.rig.pose.bones["root"].location = (4, 5, 6)
        action = bake_clip(self.rig, [self.path], [self.names], "Idle", 97)
        self.assertTrue(action.use_fake_user)
        bpy.context.scene.frame_set(1)
        first = self.rig.pose.bones[self.names[0]].matrix.copy()
        self.assertLess(self.rig.pose.bones["root"].location.length, 1e-6)
        bpy.context.scene.frame_set(25)
        self.assertAlmostEqual(self.rig.pose.bones["body"].location.z, 0.012, places=6)
        self.assertGreater(
            abs(self.rig.pose.bones[self.names[0]].rotation_euler.z), 0.01
        )
        bpy.context.scene.frame_set(97)
        last = self.rig.pose.bones[self.names[0]].matrix
        self.assertLess(
            max(
                abs(a - b)
                for row_a, row_b in zip(first, last)
                for a, b in zip(row_a, row_b)
            ),
            1e-5,
        )

    def test_walk_bake_records_planted_motion_instead_of_idle_pose(self):
        bake_clip(self.rig, [self.path], [self.names], "Walk", 49, True)
        points = []
        for frame in (1, 9, 17, 39, 49):
            bpy.context.scene.frame_set(frame)
            points.append(self.rig.pose.bones[self.names[-1]].tail.copy())
        self.assertAlmostEqual(points[0].z, 0.1, places=5)
        self.assertAlmostEqual(points[1].y - points[0].y, -0.1128205128, places=5)
        self.assertGreater(points[3].z, 0.24)
        self.assertLess((points[0] - points[-1]).length, 1e-5)

    def test_linear_interpolation_reaches_every_populated_slot(self):
        action = bpy.data.actions.new("Interpolation")
        layer = action.layers.new("Keys")
        strip = layer.strips.new(type="KEYFRAME")
        curves = []
        for name in ("First", "Second", "Empty"):
            slot = action.slots.new(id_type="OBJECT", name=name)
            if name == "Empty":
                continue
            bag = strip.channelbag(slot, ensure=True)
            curve = bag.fcurves.new(data_path="location", index=0)
            curve.keyframe_points.insert(1, 0)
            curve.keyframe_points.insert(9, 8)
            curves.append(curve)
        set_linear_interpolation(action)
        for curve in curves:
            self.assertAlmostEqual(curve.evaluate(3), 2)
            self.assertAlmostEqual(curve.evaluate(7), 6)


suite = unittest.defaultTestLoader.loadTestsFromTestCase(AnimationTests)
if not unittest.TextTestRunner(verbosity=2).run(suite).wasSuccessful():
    raise SystemExit(1)
