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
      5.5 + 2 * Math.sin(p * 2),
      (8.3 + 0.6 * Math.cos(p * 2)) * Math.sin(p + 0.7 + 0.35 * Math.sin(p * 2))
    ],
    target: [x * 0.6, 0.2, z * 0.6],
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
