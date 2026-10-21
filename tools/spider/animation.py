"""Bake the spider's authored idle motion and planted walking gait in Blender."""

import math

import bpy
from gait import toe_motion
from mathutils import Vector


def pose_walk_leg(rig, path, names, index, frame, length):
    """Pose one leg's proximal sweep and distal IK, updating joints in order."""
    hip = rig.pose.bones[names[0]]
    knee = rig.pose.bones[names[1]]
    tip = rig.pose.bones[names[2]]
    # Solve the two distal segments analytically. Each planted toe
    # stays above the dais, with an alternating lifted swing phase.
    inward = path[1] - path[3]
    inward.z = 0
    offset = (0.5 if ((index // 2 + index % 2) % 2) else 0) + (index // 2) * 0.035
    forward, height = toe_motion((frame - 1) / (length - 1) + offset)
    bpy.context.view_layer.update()
    # The proximal joint follows the foot sweep instead of waving
    # on an unrelated sine. Distal IK keeps the contact planted.
    origin = hip.head.copy()
    rest = hip.bone
    direction = path[1] - path[0] + Vector((0, forward * 0.3, height * 0.08))
    rotation = (rest.tail_local - rest.head_local).rotation_difference(direction)
    matrix = rotation.to_matrix().to_4x4() @ rest.matrix_local
    matrix.translation = origin
    hip.matrix = matrix
    bpy.context.view_layer.update()
    start = knee.head.copy()
    foot = path[3] + inward.normalized() * 0.38 + Vector((0, forward, height))
    delta = foot - start
    distance = delta.length
    axis = delta.normalized()
    l1, l2 = (
        (path[2] - path[1]).length,
        (path[3] - path[2]).length,
    )
    assert abs(l1 - l2) < distance < l1 + l2, (
        f"Walk target outside limb reach: {index} {frame} {distance} {l1 + l2}"
    )
    along = (l1 * l1 - l2 * l2 + distance * distance) / (2 * distance)
    bend = path[2] - path[1]
    bend = (bend - axis * bend.dot(axis)).normalized()
    joint = start + axis * along + bend * math.sqrt(max(0, l1 * l1 - along * along))
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


def set_linear_interpolation(action):
    """Keep baked transforms on the procedural curve between sampled frames."""
    # Set linear interpolation so baked transforms match the procedural curve.
    for layer in action.layers:
        for strip in layer.strips:
            for slot in action.slots:
                bag = strip.channelbag(slot)
                if bag:
                    for curve in bag.fcurves:
                        for key in curve.keyframe_points:
                            key.interpolation = "LINEAR"


def bake_clip(rig, paths, bone_names, name, length, walking=False):
    """Reset, pose and keyframe a seamless Idle or Walk action on the rig."""
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
        body_pose.location.z = (0.012 if walking else 0.012) * math.sin(  # noqa: RUF034
            phase * 2 if walking else phase
        )
        body_pose.rotation_euler.x = 0.004 * math.sin(phase)
        for i, names in enumerate(bone_names):
            sign = 1 if i % 2 == 0 else -1
            # Alternating tetrapod groups, L1/R2/L3/R4 against the other four.
            wave = phase + (math.pi if ((i // 2 + i % 2) % 2) else 0)
            lift = (1 - math.cos(wave)) * 0.5
            if walking:
                pose_walk_leg(rig, paths[i], names, i, frame, length)
            else:
                hip = rig.pose.bones[names[0]]
                knee = rig.pose.bones[names[1]]
                tip = rig.pose.bones[names[2]]
                hip.rotation_euler.z = sign * 0.012 * math.sin(wave)
                hip.rotation_euler.x = 0.008 * math.sin(wave)
                knee.rotation_euler.x = -0.009 * lift
                tip.rotation_euler.x = 0.008 * lift
        for bone in rig.pose.bones:
            bone.keyframe_insert("rotation_euler", frame=frame, group=bone.name)
            bone.keyframe_insert("location", frame=frame, group=bone.name)
    set_linear_interpolation(action)
    action.use_fake_user = True
    return action
