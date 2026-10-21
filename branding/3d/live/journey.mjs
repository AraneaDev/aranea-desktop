// Pure scene choreography. Distances use the same units as the imported GLB.
export const DURATION = 160
export const MODEL_SCALE = 0.65
export const WALK_SPEED = 0.22
const mix = (a, b, t) => a + (b - a) * t
const clamp = (x) => Math.max(0, Math.min(1, x))
const ease = (x) => {
  x = clamp(x)
  return x * x * (3 - 2 * x)
}
function sampleJourney(seconds) {
  const t = ((seconds % DURATION) + DURATION) % DURATION
  let x = 0,
    y = 6,
    z,
    yaw = 0,
    phase = "upper",
    walk = 0,
    speed = 0
  if (t < 50) {
    const u = t / 50
    z = mix(10, -6, ease(u))
    speed = (16 * 6 * u * (1 - u)) / 50
    walk = ease(t / 2) * ease((50 - t) / 2)
  } else if (t < 56) {
    z = -6
    phase = "anchor"
    x = 4.4 * ease((t - 50) / 6)
    yaw = (-Math.PI / 2) * ease((t - 50) / 6)
    walk = 0.7 * ease(t - 50) * ease(56 - t)
    speed = 0.4
  } else if (t < 74) {
    z = -6
    y = mix(6, -3, ease((t - 56) / 18))
    x = 4.4
    phase = "descend"
    yaw = -Math.PI / 2 - (Math.PI / 2) * ease((t - 56) / 18)
  } else if (t < 80) {
    z = -6
    y = -3
    x = 4.4 * (1 - ease((t - 74) / 6))
    phase = "landing"
    const landing = (t - 74) / 6
    yaw = Math.PI - (Math.PI / 2) * Math.sin(Math.PI * landing) ** 2
    walk = 0.7 * ease(t - 74) * ease(80 - t)
    speed = 4.4 * landing * (1 - landing)
  } else if (t < 130) {
    const u = (t - 80) / 50
    y = -3
    z = mix(-6, 10, ease(u))
    yaw = Math.PI
    phase = "lower"
    speed = (16 * 6 * u * (1 - u)) / 50
    walk = ease((t - 80) / 2) * ease((130 - t) / 2)
  } else if (t < 136) {
    y = -3
    z = 10
    phase = "anchor"
    x = -4.4 * ease((t - 130) / 6)
    yaw = Math.PI - (Math.PI / 2) * ease((t - 130) / 6)
    walk = 0.7 * ease(t - 130) * ease(136 - t)
    speed = 0.4
  } else if (t < 154) {
    z = 10
    y = mix(-3, 6, ease((t - 136) / 18))
    x = -4.4
    yaw = (Math.PI / 2) * (1 - ease((t - 136) / 18))
    phase = "ascend"
  } else {
    z = 10
    x = -4.4 * (1 - ease((t - 154) / 6))
    const landing = (t - 154) / 6
    yaw = (-Math.PI / 2) * Math.sin(Math.PI * landing) ** 2
    walk = 0.7 * ease(t - 154) * ease(160 - t)
    speed = 4.4 * landing * (1 - landing)
    phase = "landing"
  }
  const p = (t / DURATION) * Math.PI * 2
  const wide = (1 - Math.cos(p * 2)) / 2
  const angle = 0.7 + 0.5 * Math.sin(p)
  const radius = 6.3 + 6 * wide
  let cameraSide = 1
  if (t >= 130 && t < 136) cameraSide = 1 - 2 * ease((t - 130) / 6)
  else if (t >= 136 && t < 154) cameraSide = -1
  else if (t >= 154) cameraSide = -1 + 2 * ease((t - 154) / 6)
  return {
    position: [x, y, z],
    yaw,
    phase,
    walk,
    speed,
    camera: [
      x + cameraSide * radius * Math.cos(angle),
      y + 1.8 + 4.5 * wide + 1.1 * Math.sin(p * 2),
      z + radius * Math.sin(angle)
    ],
    target: [x, y + 0.5, z]
  }
}

// Use the actual route derivative rather than a guessed gait multiplier.
export function journey(seconds) {
  const t = ((seconds % DURATION) + DURATION) % DURATION
  const state = sampleJourney(t),
    before = sampleJourney(t - 0.002).position,
    after = sampleJourney(t + 0.002).position
  state.velocity = after.map((value, i) => (value - before[i]) / 0.004)
  state.speed = Math.hypot(state.velocity[0], state.velocity[2])
  state.heading =
    state.speed > 0.02 ? Math.atan2(-state.velocity[0], -state.velocity[2]) : state.yaw
  state.walk = Math.min(1, state.speed / 0.04)
  return state
}
