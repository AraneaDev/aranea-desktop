// Absolute-time envelopes make still captures and arbitrary seeking reproducible.
export function eventEnvelope(time, period, start, duration) {
  const phase = ((time % period) + period) % period
  if (phase <= start || phase >= start + duration) return 0
  return Math.sin(((phase - start) / duration) * Math.PI) ** 2
}
export function expansionState(time) {
  return {
    eclipse: eventEnvelope(time, 48, 16, 16),
    overload: eventEnvelope(time, 36, 20, 12),
    bloom: eventEnvelope(time, 42, 12, 22),
    shatter: eventEnvelope(time, 42, 25, 9)
  }
}
export function foundryParticleTravel(time, index) {
  return index * 0.19 + time * 0.7 + expansionState(time).overload * 2
}
export function crystalTwist(time, index) {
  return Math.sin(time * 0.4 + index) * 0.45 * expansionState(time).shatter
}
