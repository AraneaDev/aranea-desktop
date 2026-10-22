// Independent event timing: rare surprises, with quiet gaps and no stacking.
export const EVENT_KINDS = ["kanji-projection", "kanji-particles", "web-pulse", "mote-swarm"]
export const GLYPHS = ["影", "光", "糸", "夢", "電"]
export class EventDirector {
  constructor(random = Math.random) {
    this.random = random
    this.next = null
    this.active = null
    this.previous = null
  }
  sample(time) {
    if (this.next === null) this.next = time + 18 + this.random() * 22
    if (this.active && time >= this.active.start + this.active.duration) {
      this.active = null
      this.next = time + 35 + this.random() * 60
    }
    if (!this.active && time >= this.next) {
      const choices = EVENT_KINDS.filter((kind) => kind !== this.previous)
      const kind = choices[Math.min(choices.length - 1, Math.floor(this.random() * choices.length))]
      this.active = {
        kind,
        start: time,
        duration: 7 + this.random() * 5,
        glyph: GLYPHS[Math.min(GLYPHS.length - 1, Math.floor(this.random() * GLYPHS.length))],
        seed: this.random()
      }
      this.previous = kind
    }
    return this.active
  }
}

// Seeded absolute-time schedule lets a time= still reproduce a playback event.
// The original injectable director remains available to its other callers.
export class EventTimeline {
  constructor() {
    let seed = 8181
    const random = () => {
      seed = (seed * 1664525 + 1013904223) >>> 0
      return seed / 4294967296
    }
    this.events = []
    this.active = null
    this.activeCycle = null
    let start = 18 + random() * 22,
      previous = null
    while (start < 700) {
      const choices = EVENT_KINDS.filter((kind) => kind !== previous)
      const kind = choices[Math.floor(random() * choices.length)]
      const duration = 7 + random() * 5
      this.events.push({
        kind,
        start,
        duration,
        glyph: GLYPHS[Math.floor(random() * GLYPHS.length)],
        seed: random()
      })
      previous = kind
      start += duration + 35 + random() * 60
    }
  }
  sample(time) {
    const cycle = Math.floor(time / 720),
      local = time - cycle * 720
    const event = this.events.find((e) => local >= e.start && local < e.start + e.duration)
    if (!event) {
      this.active = null
      return null
    }
    const start = event.start + cycle * 720
    if (!this.active || this.active.start !== start || this.activeCycle !== cycle) {
      this.active = { ...event, start }
      this.activeCycle = cycle
    }
    return this.active
  }
}
