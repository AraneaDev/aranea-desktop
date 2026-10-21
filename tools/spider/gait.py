"""Grounded two-second gait in Blender's +Y forward, Z up coordinates."""

import math

DUTY = 0.65
STRIDE = 0.44
LIFT = 0.16
DURATION = 2
SCALE = 0.65
# A planted foot moves backwards at this speed relative to the model root.
WORLD_SPEED = SCALE * STRIDE / (DUTY * DURATION)


def toe_motion(phase):
    """Return forward displacement and lift, with a constant-speed stance."""
    phase = phase % 1
    if phase <= DUTY:
        return STRIDE / 2 - STRIDE * phase / DUTY, 0.0
    u = (phase - DUTY) / (1 - DUTY)
    # Match the backward stance velocity at both contact boundaries. The foot
    # briefly follows through before recovering forward during the lifted arc.
    tangent = -STRIDE / DUTY * (1 - DUTY)
    forward = (2 * u**3 - 3 * u * u + 1) * (-STRIDE / 2)
    forward += (u**3 - 2 * u * u + u) * tangent
    forward += (-2 * u**3 + 3 * u * u) * (STRIDE / 2)
    forward += (u**3 - u * u) * tangent
    return forward, LIFT * math.sin(math.pi * u) ** 2
