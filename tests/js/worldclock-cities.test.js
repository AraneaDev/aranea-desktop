// Logic contract for WorldCities.js: catalogue search, place resolution,
// list normalisation and edits, and the Elsewhen auto-seed detection. No QML,
// no I/O; run with `node --test tests/js/` (tools/check runs it with coverage).

const assert = require("node:assert/strict")
const path = require("node:path")
const fs = require("node:fs")
const { test } = require("node:test")

const dir = path.join(__dirname, "..", "..", "plugins/araneadev.worldclock")
const cities = require(path.join(dir, "WorldCities.js"))
const rows = JSON.parse(fs.readFileSync(path.join(dir, "cities.json"), "utf8"))
const cat = cities.parseCatalog(rows)
const HOME = "Europe/Amsterdam"
const SEED = cities.SEED

/** Offsets (minutes east of UTC) for every zone at 2026-10-20 via Node's tz data. */
function offsetsAt(zones, utcMs) {
  const out = {}
  zones.forEach((z) => {
    const f = new Intl.DateTimeFormat("en-US", {
      timeZone: z,
      hourCycle: "h23",
      year: "numeric",
      month: "numeric",
      day: "numeric",
      hour: "numeric",
      minute: "numeric"
    })
    const p = {}
    f.formatToParts(new Date(utcMs)).forEach((x) => (p[x.type] = Number(x.value)))
    out[z] = Math.round((Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute) - utcMs) / 60000)
  })
  return out
}
const OFFSETS = offsetsAt(cities.seedCandidateZones().concat([HOME]), Date.UTC(2026, 9, 20, 10, 13))
const TIM_HOME = [
  { name: "Amsterdam", zone: "Europe/Amsterdam", lat: 52.37, lon: 4.89, home: true },
  { name: "Delhi", zone: "Asia/Kolkata", lat: 28.65, lon: 77.23 },
  { name: "Tokyo", zone: "Asia/Tokyo", lat: 35.69, lon: 139.69 },
  { name: "Los Angeles", zone: "America/Los_Angeles", lat: 34.05, lon: -118.24 },
  { name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01 }
]
const TIM = TIM_HOME.map((c) => ({ name: c.name, zone: c.zone, lat: c.lat, lon: c.lon })) // upstream writes no `home`

test("normalize: fallback is a copy, SEED stays intact", () => {
  const n = cities.normalize(undefined, HOME)
  n[0].name = "X"
  n.pop()
  assert.equal(SEED.length, 5)
  assert.equal(SEED[0].name, "Amsterdam")
})

test("SEED: five cities, Amsterdam home, UTC without coordinates", () => {
  assert.deepEqual(
    SEED.map((c) => c.zone),
    ["Europe/Amsterdam", "Europe/London", "UTC", "America/New_York", "America/Los_Angeles"]
  )
  assert.equal(SEED[0].home, true)
  assert.equal(SEED.filter((c) => c.home).length, 1)
  assert.equal(typeof SEED[1].lat, "number")
  assert.equal(SEED[2].lat, undefined)
  assert.deepEqual(cities.UTC_ENTRY, { name: "UTC", zone: "UTC" })
})

test("parseCatalog: fields and country from the tz region", () => {
  const c = cities.parseCatalog([["New York", "America/New_York", 40.71, -74.01, 1]])
  assert.deepEqual(c[0], {
    name: "New York",
    zone: "America/New_York",
    lat: 40.71,
    lon: -74.01,
    rank: 1,
    country: "America"
  })
  assert.equal(cities.parseCatalog([["X", "UTC", 0, 0, 1]])[0].country, "")
})

test("search: prefix before substring, case-insensitive, UTC, empty", () => {
  const names = cities.search(cat, "to").map((c) => c.name)
  assert.deepEqual(names.slice(0, 2).sort(), ["Tokyo", "Toronto"])
  const first = cat.filter((c) => c.name.toLowerCase().indexOf("to") === 0).length
  names.slice(0, Math.min(first, 5)).forEach((n) => assert.ok(n.toLowerCase().indexOf("to") === 0))
  assert.equal(cities.search(cat, "utc")[0].zone, "UTC")
  assert.deepEqual(cities.search(cat, ""), [])
  assert.equal(cities.search(cat, "TOK")[0].name, "Tokyo")
  assert.equal(cities.search(cat, "o", 3).length, 3)
  // substring match after prefixes, ordered by rank then name
  const sub = cities.search(cat, "ok", 50)
  assert.ok(sub.length > 0)
  assert.ok(sub.every((c) => c.name.toLowerCase().indexOf("ok") >= 0))
  // ties on rank fall back to name
  const tie = cities.search(
    [
      { name: "Bb", zone: "Asia/B", lat: 0, lon: 0, rank: 1 },
      { name: "Ba", zone: "Asia/A", lat: 0, lon: 0, rank: 1 }
    ],
    "b"
  )
  assert.deepEqual(
    tie.map((c) => c.name),
    ["Ba", "Bb"]
  )
  // rank ordering inside the prefix tier, and prefix vs substring tiers
  const r = cities.search(
    [
      { name: "Xb", zone: "Asia/B", lat: 0, lon: 0, rank: 3 },
      { name: "Xa", zone: "Asia/A", lat: 0, lon: 0, rank: 1 },
      { name: "aX", zone: "Asia/C", lat: 0, lon: 0, rank: 1 }
    ],
    "x"
  )
  assert.deepEqual(
    r.map((c) => c.name),
    ["Xa", "Xb", "aX"]
  )
})

test("resolvePlace: exact, zone-unique, unchanged", () => {
  const d = cities.resolvePlace({ name: "Delhi", zone: "Asia/Kolkata" }, cat)
  assert.equal(typeof d.lat, "number")
  assert.equal(typeof d.lon, "number")
  const u = cities.resolvePlace({ name: "Mumbai-ish", zone: "Asia/Kolkata" }, cat)
  assert.equal(typeof u.lat, "number")
  const n = { name: "Nowhere", zone: "Etc/GMT+3" }
  assert.deepEqual(cities.resolvePlace(n, cat), n)
  // ambiguous zone and unknown name: unchanged
  const amb = [
    { name: "A", zone: "Asia/Z", lat: 1, lon: 2, rank: 1 },
    { name: "B", zone: "Asia/Z", lat: 3, lon: 4, rank: 1 }
  ]
  const x = { name: "C", zone: "Asia/Z" }
  assert.deepEqual(cities.resolvePlace(x, amb), x)
  assert.equal(cities.resolvePlace({ name: "B", zone: "Asia/Z" }, amb).lat, 3)
})

test("normalize: seed fallback, validation, dedupe, one home", () => {
  assert.deepEqual(cities.normalize(undefined, HOME), SEED)
  assert.deepEqual(cities.normalize([], HOME), SEED)
  assert.deepEqual(cities.normalize("x", HOME), SEED)
  assert.deepEqual(cities.normalize([null, { name: "x" }, { zone: "bad zone" }], HOME), SEED)
  const two = [
    { name: "A", zone: "Europe/Paris" },
    { name: "B", zone: "Europe/Amsterdam" }
  ]
  const a = cities.normalize(two, HOME)
  assert.equal(a[1].home, true)
  assert.equal(a[0].home, undefined)
  const kept = cities.normalize([{ name: "A", zone: "Europe/Paris", home: true }, two[1]], HOME)
  assert.equal(kept[0].home, true)
  assert.equal(kept[1].home, undefined)
  const dbl = cities.normalize(
    [
      { name: "A", zone: "Europe/Paris", home: true },
      { name: "B", zone: "Europe/Amsterdam", home: true }
    ],
    HOME
  )
  assert.deepEqual(
    dbl.map((c) => !!c.home),
    [true, false]
  )
  const first = cities.normalize([{ name: "A", zone: "Europe/Paris" }], HOME)
  assert.equal(first[0].home, true)
  const dup = cities.normalize(
    [
      { name: "A", zone: "Europe/Paris" },
      { name: "A", zone: "Europe/Paris" },
      { name: "A", zone: "UTC" },
      { name: "", zone: "UTC" },
      { name: "Z", zone: "America/Argentina/Buenos_Aires", lat: "x", lon: 1 }
    ],
    HOME
  )
  assert.equal(dup.length, 3)
  assert.equal(dup[2].lat, undefined)
  assert.equal(dup[2].lon, 1)
})

test("removeAt, move, setHome, add", () => {
  assert.equal(cities.removeAt(SEED, 0), SEED)
  assert.equal(cities.removeAt(SEED, 9), SEED)
  assert.equal(cities.removeAt(SEED, 4).length, 4)
  assert.equal(cities.move(SEED, 0, -1).index, 0)
  assert.equal(cities.move(SEED, 0, -1).cities, SEED)
  assert.equal(cities.move(SEED, 4, 1).index, 4)
  assert.equal(cities.move(SEED, 9, 1).index, 9)
  const m = cities.move(SEED, 1, 1)
  assert.equal(m.index, 2)
  assert.deepEqual(
    m.cities.slice(1, 3).map((c) => c.name),
    ["UTC", "London"]
  )
  assert.equal(SEED[1].name, "London")
  const h = cities.setHome(SEED, 3)
  assert.deepEqual(
    h.map((c) => !!c.home),
    [false, false, false, true, false]
  )
  assert.equal(SEED[0].home, true)
  assert.equal(cities.setHome(SEED, 9), SEED)
  assert.equal(cities.add(SEED, { name: "Tokyo", zone: "Asia/Tokyo" }).index, 5)
  const again = cities.add(SEED, { name: "London", zone: "Europe/London" })
  assert.equal(again.index, 1)
  assert.equal(again.cities.length, 5)
  const added = cities.add(SEED, { name: "Tokyo", zone: "Asia/Tokyo", home: true })
  assert.equal(added.cities[5].home, undefined)
})

test("serialize: strips undefined keys, keeps order", () => {
  const s = cities.serialize([
    { name: "A", zone: "UTC", lat: undefined, lon: undefined, home: undefined },
    { name: "B", zone: "Asia/Tokyo", lat: 1, lon: 2, home: true }
  ])
  assert.deepEqual(s, [
    { name: "A", zone: "UTC" },
    { name: "B", zone: "Asia/Tokyo", lat: 1, lon: 2, home: true }
  ])
  assert.deepEqual(Object.keys(s[1]), ["name", "zone", "lat", "lon", "home"])
})

test("seedCandidateZones: the 34 upstream candidates", () => {
  const z = cities.seedCandidateZones()
  assert.equal(z.length, 34)
  assert.equal(z[0], "Pacific/Honolulu")
  assert.ok(z.indexOf("Asia/Kolkata") >= 0)
})

test("isElsewhenAutoSeed: Tim's live list, edits, SEED, degenerate input", () => {
  assert.equal(cities.isElsewhenAutoSeed(TIM, HOME, OFFSETS), true)
  assert.equal(cities.isElsewhenAutoSeed(TIM_HOME, HOME, OFFSETS), true)
  assert.equal(
    cities.isElsewhenAutoSeed(
      TIM.filter((c) => c.name !== "Delhi"),
      HOME,
      OFFSETS
    ),
    false
  )
  assert.equal(cities.isElsewhenAutoSeed(SEED, HOME, OFFSETS), false)
  assert.equal(cities.isElsewhenAutoSeed(TIM, HOME, {}), false)
  assert.equal(cities.isElsewhenAutoSeed(TIM, HOME, null), false)
  assert.equal(cities.isElsewhenAutoSeed(null, HOME, OFFSETS), false)
  assert.equal(cities.isElsewhenAutoSeed(TIM, "", OFFSETS), false)
  // a home that is not the system zone is not an untouched seed
  assert.equal(cities.isElsewhenAutoSeed(TIM, "Europe/Paris", OFFSETS), false)
})

test("pickSeedZones: relaxes the gap when the world is crowded", () => {
  const home = { label: "H", id: "Etc/H" }
  const off = { "Etc/H": 0 }
  // only candidates within 2h of home: gap 180 and 120 fail, 60 succeeds
  off["Europe/London"] = 60
  off["Europe/Paris"] = 120
  off["Europe/Berlin"] = -120
  off["Europe/Rome"] = -60
  const p = cities.pickSeedZones(home, off, 4)
  assert.equal(p.length, 4)
  assert.deepEqual(cities.pickSeedZones(null, off), [])
  assert.deepEqual(cities.pickSeedZones(home, null), [])
  assert.deepEqual(cities.pickSeedZones(home, {}), [])
  assert.equal(cities.pickSeedZones(home, { "Etc/H": 0, "Europe/Paris": 600 }).length, 1)
  // a candidate sharing home's id or label is skipped; ties on dial distance clash
  const same = { label: "Paris", id: "Europe/Lisbon" }
  const o2 = { "Europe/Lisbon": 0, "Europe/Paris": 600, "Europe/London": 600 }
  assert.deepEqual(
    cities.pickSeedZones(same, o2, 4).map((c) => c.id),
    ["Europe/London"]
  )
  const o3 = { "Europe/Paris": 0, "Europe/London": 600 }
  assert.deepEqual(
    cities.pickSeedZones({ label: "x", id: "Europe/Paris" }, o3).map((c) => c.id),
    ["Europe/London"]
  )
  assert.deepEqual(cities.seedZones(home, off, 1).length, 2)
  assert.deepEqual(cities.seedZones(null, off), [])
})
