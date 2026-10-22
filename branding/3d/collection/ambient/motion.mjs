const mod = (n, m) => ((n % m) + m) % m
export function cityDepth(index, time) {
  return mod(264 - index * 12 + time * 14.4, 288) - 276
}
export function ribbonPoint(u, v, time, layer) {
  const x = (u - 0.5) * 72
  const wave = u * 7 + time * 0.24 + layer * 0.8
  const burst = silkBurst(time)
  const braid = u * Math.PI * 4 + (layer * Math.PI * 2) / 7 + time * 0.42
  return [
    x,
    Math.sin(wave) * 4 +
      Math.sin(u * 13 - time * 0.17) * 1.3 +
      v * (3 + Math.sin(wave) * 1.2) +
      (layer - 3) * 1.7 +
      burst * Math.sin(braid) * 6,
    -12 -
      layer * 3 +
      Math.cos(wave * 0.8) * 5 +
      v * Math.sin(wave) * 2 +
      burst * Math.cos(braid) * 7
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

// Zero velocity at both boundaries avoids a visible cut when the event repeats.
function pulse(time, period, start, duration) {
  const phase = mod(time, period) - start
  return phase <= 0 || phase >= duration ? 0 : Math.sin((phase / duration) * Math.PI) ** 2
}
export function glyphFormation(time) {
  return pulse(time, 48, 20, 16)
}
export function silkBurst(time) {
  return pulse(time, 44, 18, 14)
}
export function transitState(time) {
  const phase = mod(time, 42) - 12
  const progress = Math.max(0, Math.min(1, phase / 12))
  return { x: (progress - 0.5) * 100, opacity: pulse(time, 42, 12, 12) }
}
