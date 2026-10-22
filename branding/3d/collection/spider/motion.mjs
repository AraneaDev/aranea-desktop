const TAU = Math.PI * 2
export function weaver(seconds) {
  const p = (seconds / 120) * TAU
  const angle = p + 0.09 * Math.sin(p * 2)
  const rate = (TAU / 120) * (1 + 0.18 * Math.cos(p * 2))
  const x = 6 * Math.cos(angle),
    z = 6 * Math.sin(angle)
  return {
    position: [x, 0, z],
    heading: Math.atan2(Math.sin(angle), -Math.cos(angle)),
    speed: 6 * rate,
    distance: 6 * angle,
    walk: 1,
    phase: "weave",
    camera: [
      (8.3 + 0.6 * Math.cos(p * 2)) * Math.cos(p + 0.7 + 0.35 * Math.sin(p * 2)),
      6.5 + 2 * Math.sin(p * 2),
      (8.3 + 0.6 * Math.cos(p * 2)) * Math.sin(p + 0.7 + 0.35 * Math.sin(p * 2))
    ],
    target: [x, 0.4, z],
    progress: (((seconds / 120) % 1) + 1) % 1
  }
}
export function spiderfall(seconds) {
  const p = (seconds / 96) * TAU
  const y = -12 + 16 * Math.cos(p)
  const x = 0.45 * Math.sin(p * 3),
    z = 0.35 * Math.sin(p * 2)
  return {
    position: [x, y, z],
    anchor: [0, 12, 0],
    heading: 0.25 * Math.sin(p * 2),
    speed: 0,
    distance: 0,
    walk: 0,
    phase: Math.sin(p) >= 0 ? "descend" : "ascend",
    camera: [3.7 * Math.cos(p + 0.6), y + 3 + 1.2 * Math.sin(p * 2), 3.7 * Math.sin(p + 0.6)],
    target: [0, y - 0.6, 0],
    progress: (((seconds / 96) % 1) + 1) % 1
  }
}

// One restrained structural transformation per route. Pure absolute time also
// makes a captured still agree with the same moment reached during playback.
export function loomState(seconds, fall = false) {
  const duration = fall ? 96 : 120
  const u = (((seconds / duration) % 1) + 1) % 1
  const distance = Math.abs(u - (fall ? 0.5 : 0.87))
  const resonance = distance < 0.085 ? Math.cos(((distance / 0.085) * Math.PI) / 2) ** 2 : 0
  return {
    resonance,
    aperture: 4.6 - 1.6 * resonance,
    rotation: 0.12 * Math.sin(u * TAU),
    scanHeight: 12 - 54 * u
  }
}

// A single Points buffer carries silk impulses; no per-particle objects or draws.
export function writeLoomSignals(target, seconds, fall = false) {
  const count = target.length / 3
  for (let i = 0; i < count; i++) {
    const u = (((i / count + seconds * (fall ? 0.045 : 0.075)) % 1) + 1) % 1
    const angle = fall ? i * 2.39996 + seconds * 0.3 : (Math.floor(i / 8) * TAU) / (count / 8)
    const radius = fall ? 3.15 + 0.45 * Math.sin(u * TAU * 3) : 0.25 + u * 4.45
    target[i * 3] = Math.cos(angle) * radius
    target[i * 3 + 1] = fall ? 14 - u * 56 : 0.18 + 0.045 * Math.sin(u * TAU * 4)
    target[i * 3 + 2] = Math.sin(angle) * radius
  }
}
