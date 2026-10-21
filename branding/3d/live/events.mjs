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
