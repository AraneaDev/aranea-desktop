"""Run with Blender: structural checks for the generated reusable character."""

import math
import bpy


def validate(rig):
    assert rig.type == "ARMATURE"
    assert len(rig.data.bones) == 26, "root + body + three bones per leg"
    assert all(
        f"leg.{side}{i}.{part}" in rig.data.bones
        for side in ("L", "R")
        for i in range(1, 5)
        for part in ("hip", "knee", "tip")
    )
    meshes = [o for o in bpy.data.collections["Character"].objects if o.type == "MESH"]
    assert len(meshes) >= 12
    for obj in meshes:
        assert all(math.isfinite(c) for v in obj.data.vertices for c in v.co)
        assert any(m.type == "ARMATURE" and m.object == rig for m in obj.modifiers), (
            obj.name
        )
        for vertex in obj.data.vertices:
            assert abs(sum(g.weight for g in vertex.groups) - 1) < 1e-4, obj.name
    for name, end in [("Idle", 97), ("Walk", 49)]:
        action = bpy.data.actions.get(name)
        assert action, name
        rig.animation_data.action = action
        bpy.context.scene.frame_set(1)
        first = [b.matrix.copy() for b in rig.pose.bones]
        bpy.context.scene.frame_set(end)
        assert all(
            max(abs(a[i][j] - b.matrix[i][j]) for i in range(4) for j in range(4))
            < 1e-5
            for a, b in zip(first, rig.pose.bones)
        ), name + " does not loop"
        bpy.context.scene.frame_set(end // 2)
        assert any(
            max(abs(a[i][j] - b.matrix[i][j]) for i in range(4) for j in range(4))
            > 0.001
            for a, b in zip(first, rig.pose.bones)
        ), name + " is static"
    rig.animation_data.action = bpy.data.actions["Walk"]
    heights = []
    for frame in range(1, 50):
        bpy.context.scene.frame_set(frame)
        heights.extend(b.tail.z for b in rig.pose.bones if b.name.endswith(".tip"))
    assert min(heights) > 0.08, "Walk toes intersect the dais"
    assert max(heights) > 0.24, "Walk has no swing phase"
    print("SPIDER_VALIDATED: 8 legs, 26 bones, normalized weights, Idle/Walk loops")


def validate_preview(scene, rig):
    """The published scene must show every leg moving, independently of camera motion."""
    assert rig.animation_data.action.name == "Walk", "Preview must use the walking clip"
    assert scene.frame_end == 48, "Preview must omit the duplicate loop endpoint"
    saved_frame = scene.frame_current
    paths = {b.name: [] for b in rig.pose.bones if b.name.endswith(".tip")}
    try:
        for frame in range(1, 50):
            scene.frame_set(frame)
            for name, points in paths.items():
                points.append(rig.pose.bones[name].tail.copy())
        for name, points in paths.items():
            travel = max((a - b).length for a in points for b in points)
            assert travel >= 0.35, f"{name} barely moves: {travel:.3f}"
        scene.frame_set(1)
        start = scene.camera.matrix_world.copy()
        scene.frame_set(49)
        end = scene.camera.matrix_world
        assert (
            max(abs(start[i][j] - end[i][j]) for i in range(4) for j in range(4)) < 1e-5
        ), "Camera does not loop with legs"
    finally:
        scene.frame_set(saved_frame)
    print(
        "SPIDER_PREVIEW_VALIDATED: visible movement on all 8 legs; camera and rig share loop timing"
    )


def validate_gait(rig):
    """Check actual posed toes: stance pushes backwards, at floor height."""
    from gait import DUTY, STRIDE

    rig.animation_data.action = bpy.data.actions["Walk"]
    previous = {}
    for frame in range(1, 50):
        bpy.context.scene.frame_set(frame)
        for pair in range(4):
            for side in range(2):
                name = f"leg.{'L' if side == 0 else 'R'}{pair + 1}.tip"
                offset = (0.5 if (pair + side) % 2 else 0) + pair * 0.035
                phase = ((frame - 1) / 48 + offset) % 1
                point = rig.pose.bones[name].tail.copy()
                if phase <= DUTY:
                    assert abs(point.z - 0.1) < 0.0002, name + " is not planted"
                    if name in previous:
                        prev_phase, prev_point = previous[name]
                        if prev_phase <= DUTY and phase > prev_phase:
                            expected = -STRIDE / DUTY / 48
                            assert abs(point.y - prev_point.y - expected) < 0.0002, (
                                name + " stance slides forwards or changes speed"
                            )
                previous[name] = (phase, point)
    print(
        "SPIDER_GAIT_VALIDATED: all eight feet plant and push backwards at constant speed"
    )
