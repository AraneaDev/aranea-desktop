const mod = (n, m) => ((n % m) + m) % m
export function cityDepth(index, time) {
  return mod(264 - index * 12 + time * 14.4, 288) - 276
}
export function ribbonPoint(u, v, time, layer) {
  const x = (u - 0.5) * 72
  const wave = u * 7 + time * 0.24 + layer * 0.8
  return [
    x,
    Math.sin(wave) * 4 +
      Math.sin(u * 13 - time * 0.17) * 1.3 +
      v * (3 + Math.sin(wave) * 1.2) +
      (layer - 3) * 1.7,
    -12 - layer * 3 + Math.cos(wave * 0.8) * 5 + v * Math.sin(wave) * 2
  ]
}
export function glyphPhase(index, time) {
  const t = time + index * 1.71
  const phase = mod(t, 12)
  return { cycle: Math.floor(t / 12), dissolve: Math.max(0, Math.min(1, (phase - 6) / 3)) }
}
export function renderScale(w, h, dpr) {
  return Math.min(dpr, 1.4, Math.sqrt(2100000 / (w * h)))
}
