// WorldCities: the city catalogue search, the saved list's edits and
// validation, and the Elsewhen first-run seed rules the world clock uses to
// recognise (and replace) an untouched Omarchy list. Pure logic: no QML, no
// I/O, no Intl; the Panel loads cities.json and passes the parsed rows in.
//
// SEED_CANDIDATES, pickSeedAt, pickSeedZones and seedZones are ported
// unchanged from Omarchy's omarchy.elsewhen panel
// (/usr/share/omarchy/shell/plugins/panels/elsewhen/Model.js), MIT licence,
// Copyright Jason Fried / Omarchy, so isElsewhenAutoSeed reproduces exactly
// the list Elsewhen would have seeded.

var DAY_MINUTES = 1440
var ZONE_RE = /^[A-Za-z_]+(\/[A-Za-z0-9_+-]+)*$/

/** The first-run list: Amsterdam (home), London, UTC, New York, Los Angeles. */
var SEED = [
  { name: "Amsterdam", zone: "Europe/Amsterdam", lat: 52.37, lon: 4.89, home: true },
  { name: "London", zone: "Europe/London", lat: 51.51, lon: -0.13 },
  { name: "UTC", zone: "UTC" },
  { name: "New York", zone: "America/New_York", lat: 40.71, lon: -74.01 },
  { name: "Los Angeles", zone: "America/Los_Angeles", lat: 34.05, lon: -118.24 }
]

var UTC_ENTRY = { name: "UTC", zone: "UTC" }

/**
 * Turns the bundled cities.json rows into catalogue records.
 * @param {Array<Array>} rows [name, tz, lat, lon, rank]
 * @returns {Array<{name:string,zone:string,lat:number,lon:number,rank:number,country:string}>}
 */
function parseCatalog(rows) {
  var out = []
  for (var i = 0; i < rows.length; i++) {
    var r = rows[i]
    var slash = String(r[1]).indexOf("/")
    out.push({
      name: r[0],
      zone: r[1],
      lat: r[2],
      lon: r[3],
      rank: r[4],
      country: slash > 0 ? String(r[1]).substring(0, slash) : ""
    })
  }
  return out
}

/**
 * Case-insensitive catalogue search: prefix matches first, then substring
 * matches, each ordered by rank then name. "UTC" is offered as an entry.
 * @param {Array} catalog parseCatalog output
 * @param {string} query
 * @param {number} [limit=5]
 * @returns {Array} City records with rank
 */
function search(catalog, query, limit) {
  var max = limit === undefined ? 5 : limit
  var q = String(query || "").toLowerCase()
  if (q === "") return []
  var pool = catalog.slice()
  pool.push({ name: "UTC", zone: "UTC", rank: 1 })
  var hits = []
  for (var i = 0; i < pool.length; i++) {
    var at = pool[i].name.toLowerCase().indexOf(q)
    if (at >= 0) hits.push({ city: pool[i], tier: at === 0 ? 0 : 1 })
  }
  hits.sort(function (a, b) {
    if (a.tier !== b.tier) return a.tier - b.tier
    if (a.city.rank !== b.city.rank) return a.city.rank - b.city.rank
    return a.city.name < b.city.name ? -1 : a.city.name > b.city.name ? 1 : 0
  })
  var out = []
  for (var j = 0; j < hits.length && out.length < max; j++) {
    var c = hits[j].city
    var rec = { name: c.name, zone: c.zone, rank: c.rank }
    if (c.lat !== undefined) {
      rec.lat = c.lat
      rec.lon = c.lon
    }
    out.push(rec)
  }
  return out
}

/**
 * Fills a city's coordinates from the catalogue: exact zone + name, else the
 * zone alone when exactly one row has it; otherwise the city is returned as is.
 * @param {{name:string,zone:string}} city
 * @param {Array} catalog
 * @returns {Object} city
 */
function resolvePlace(city, catalog) {
  var byZone = []
  for (var i = 0; i < catalog.length; i++) {
    if (catalog[i].zone !== city.zone) continue
    if (catalog[i].name === city.name) return withCoords(city, catalog[i])
    byZone.push(catalog[i])
  }
  return byZone.length === 1 ? withCoords(city, byZone[0]) : city
}

function withCoords(city, row) {
  var out = {}
  for (var k in city) out[k] = city[k]
  out.lat = row.lat
  out.lon = row.lon
  return out
}

function validCity(c) {
  return (
    !!c &&
    typeof c === "object" &&
    typeof c.name === "string" &&
    c.name !== "" &&
    typeof c.zone === "string" &&
    (c.zone === "UTC" || ZONE_RE.test(c.zone))
  )
}

function copyCity(c, keepHome) {
  var out = { name: c.name, zone: c.zone }
  if (typeof c.lat === "number") out.lat = c.lat
  if (typeof c.lon === "number") out.lon = c.lon
  if (keepHome && c.home === true) out.home = true
  return out
}

/**
 * Cleans a stored list: drops invalid rows and duplicates, and guarantees one
 * home (existing flag, else the system zone, else the first row).
 * @param {*} list stored value
 * @param {string} systemZone
 * @returns {Array} cities; SEED when nothing valid is stored
 */
function normalize(list, systemZone) {
  var out = []
  var seen = {}
  if (Array.isArray(list)) {
    for (var i = 0; i < list.length; i++) {
      if (!validCity(list[i])) continue
      var key = list[i].zone + "\n" + list[i].name
      if (seen[key]) continue
      seen[key] = true
      out.push(copyCity(list[i], true))
    }
  }
  if (out.length === 0) return serialize(SEED)
  var home = -1
  for (var j = 0; j < out.length; j++) {
    if (out[j].home) {
      if (home < 0) home = j
      else delete out[j].home
    }
  }
  if (home < 0) {
    for (var k = 0; k < out.length && home < 0; k++) if (out[k].zone === systemZone) home = k
    if (home < 0) home = 0
    out[home].home = true
  }
  return out
}

/** Appends a city (never as home); an existing zone + name returns its index. */
function add(list, city) {
  for (var i = 0; i < list.length; i++)
    if (list[i].zone === city.zone && list[i].name === city.name) return { cities: list, index: i }
  var next = list.slice()
  next.push(copyCity(city, false))
  return { cities: next, index: next.length - 1 }
}

/** Removes row i; the home row (and a bad index) is refused. */
function removeAt(list, i) {
  if (i < 0 || i >= list.length || list[i].home) return list
  var next = list.slice()
  next.splice(i, 1)
  return next
}

/** Moves row i by one place, clamped at the ends. */
function move(list, i, delta) {
  var to = i + delta
  if (i < 0 || i >= list.length || to < 0 || to >= list.length) return { cities: list, index: i }
  var next = list.slice()
  var item = next[i]
  next[i] = next[to]
  next[to] = item
  return { cities: next, index: to }
}

/** Makes row i the only home. */
function setHome(list, i) {
  if (i < 0 || i >= list.length) return list
  var next = []
  for (var j = 0; j < list.length; j++) next.push(copyCity(list[j], false))
  next[i].home = true
  return next
}

/** The list as stored: only defined keys, original order. */
function serialize(list) {
  var out = []
  for (var i = 0; i < list.length; i++) out.push(copyCity(list[i], true))
  return out
}

// ---- Elsewhen first-run seed (upstream port)

// Home plus four well-known cities spread round the clock from it. Rank breaks ties.
var SEED_CANDIDATES = [
  { label: "Honolulu", id: "Pacific/Honolulu", rank: 3 },
  { label: "Anchorage", id: "America/Anchorage", rank: 3 },
  { label: "Los Angeles", id: "America/Los_Angeles", rank: 2 },
  { label: "Vancouver", id: "America/Vancouver", rank: 3 },
  { label: "Mexico City", id: "America/Mexico_City", rank: 3 },
  { label: "Chicago", id: "America/Chicago", rank: 3 },
  { label: "New York", id: "America/New_York", rank: 1 },
  { label: "Sao Paulo", id: "America/Sao_Paulo", rank: 2 },
  { label: "Buenos Aires", id: "America/Argentina/Buenos_Aires", rank: 3 },
  { label: "Reykjavik", id: "Atlantic/Reykjavik", rank: 3 },
  { label: "London", id: "Europe/London", rank: 1 },
  { label: "Lisbon", id: "Europe/Lisbon", rank: 3 },
  { label: "Paris", id: "Europe/Paris", rank: 1 },
  { label: "Berlin", id: "Europe/Berlin", rank: 3 },
  { label: "Madrid", id: "Europe/Madrid", rank: 3 },
  { label: "Rome", id: "Europe/Rome", rank: 3 },
  { label: "Cairo", id: "Africa/Cairo", rank: 3 },
  { label: "Johannesburg", id: "Africa/Johannesburg", rank: 3 },
  { label: "Istanbul", id: "Europe/Istanbul", rank: 3 },
  { label: "Moscow", id: "Europe/Moscow", rank: 3 },
  { label: "Nairobi", id: "Africa/Nairobi", rank: 3 },
  { label: "Dubai", id: "Asia/Dubai", rank: 2 },
  { label: "Karachi", id: "Asia/Karachi", rank: 3 },
  { label: "Delhi", id: "Asia/Kolkata", rank: 2 },
  { label: "Bangkok", id: "Asia/Bangkok", rank: 3 },
  { label: "Jakarta", id: "Asia/Jakarta", rank: 3 },
  { label: "Singapore", id: "Asia/Singapore", rank: 2 },
  { label: "Hong Kong", id: "Asia/Hong_Kong", rank: 2 },
  { label: "Shanghai", id: "Asia/Shanghai", rank: 2 },
  { label: "Perth", id: "Australia/Perth", rank: 3 },
  { label: "Seoul", id: "Asia/Seoul", rank: 3 },
  { label: "Tokyo", id: "Asia/Tokyo", rank: 1 },
  { label: "Sydney", id: "Australia/Sydney", rank: 2 },
  { label: "Auckland", id: "Pacific/Auckland", rank: 3 }
]

/** Every zone pickSeedZones may consult; the Panel probes these for offsets. */
function seedCandidateZones() {
  var out = []
  for (var i = 0; i < SEED_CANDIDATES.length; i++) out.push(SEED_CANDIDATES[i].id)
  return out
}

// Minutes east of home, wrapped to one turn of the dial.
function eastOf(offsetMinutes, homeMinutes) {
  var d = (offsetMinutes - homeMinutes) % DAY_MINUTES
  return d < 0 ? d + DAY_MINUTES : d
}

function dialDistance(a, b) {
  var d = Math.abs(a - b) % DAY_MINUTES
  return Math.min(d, DAY_MINUTES - d)
}

// Best-ranked candidates first, each at least `gap` minutes from home and from every pick.
function pickSeedAt(home, offsets, count, gap) {
  var homeOff = offsets[home.id]
  var homeLabel = String(home.label || "").toLowerCase()
  var picked = []
  for (var r = 1; r <= 3; r++) {
    for (var j = 0; j < SEED_CANDIDATES.length && picked.length < count; j++) {
      var c = SEED_CANDIDATES[j]
      if (c.rank !== r) continue
      var off = offsets[c.id]
      if (off === undefined || off === null) continue
      if (c.id === home.id) continue
      if (String(c.label).toLowerCase() === homeLabel) continue
      var east = eastOf(off, homeOff)
      if (Math.min(east, DAY_MINUTES - east) < gap) continue
      var clash = false
      for (var k = 0; k < picked.length; k++)
        if (dialDistance(picked[k].east, east) < gap) {
          clash = true
          break
        }
      if (clash) continue
      picked.push({ label: c.label, id: c.id, east: east })
    }
  }
  return picked
}

/** `offsets` maps zone id to minutes east of UTC and must include home's. */
function pickSeedZones(home, offsets, count) {
  var n = count === undefined ? 4 : count
  if (!home || !home.id || !offsets) return []
  if (offsets[home.id] === undefined || offsets[home.id] === null) return []

  // Relax the gap where half the world sits within a couple of hours of home.
  var picked = []
  var gaps = [180, 120, 60]
  for (var g = 0; g < gaps.length; g++) {
    picked = pickSeedAt(home, offsets, n, gaps[g])
    if (picked.length >= n) break
  }

  picked.sort(function (a, b) {
    return a.east - b.east
  })

  var out = []
  for (var m = 0; m < picked.length; m++) out.push({ label: picked[m].label, id: picked[m].id })
  return out
}

function seedZones(home, offsets, count) {
  if (!home || !home.id) return []
  var out = [{ label: home.label, id: home.id }]
  var rest = pickSeedZones(home, offsets, count)
  for (var i = 0; i < rest.length; i++) out.push(rest[i])
  return out
}

/**
 * True when `list` is exactly the list Omarchy's Elsewhen would have seeded for
 * `homeZone` (so it can be replaced by the Aranea seed), false once edited.
 * @param {Array} list saved cities
 * @param {string} homeZone the system zone
 * @param {Object} offsets {[zone]: minutes east of UTC}, incl. seedCandidateZones()
 * @returns {boolean}
 */
function isElsewhenAutoSeed(list, homeZone, offsets) {
  if (!Array.isArray(list) || !homeZone || !offsets) return false
  var homeRow = null
  for (var i = 0; i < list.length; i++) if (list[i] && list[i].home) homeRow = list[i]
  // Upstream never writes `home`; its home is the row for the system zone.
  if (!homeRow)
    for (var h = 0; h < list.length && !homeRow; h++)
      if (list[h] && list[h].zone === homeZone) homeRow = list[h]
  if (!homeRow || homeRow.zone !== homeZone) return false
  var want = seedZones({ label: homeRow.name, id: homeZone }, offsets)
  if (want.length !== list.length) return false
  for (var j = 0; j < want.length; j++)
    if (list[j].zone !== want[j].id || list[j].name !== want[j].label) return false
  return true
}

if (typeof module !== "undefined")
  module.exports = {
    SEED: SEED,
    UTC_ENTRY: UTC_ENTRY,
    parseCatalog: parseCatalog,
    search: search,
    resolvePlace: resolvePlace,
    normalize: normalize,
    add: add,
    removeAt: removeAt,
    move: move,
    setHome: setHome,
    serialize: serialize,
    seedCandidateZones: seedCandidateZones,
    pickSeedZones: pickSeedZones,
    seedZones: seedZones,
    isElsewhenAutoSeed: isElsewhenAutoSeed
  }
