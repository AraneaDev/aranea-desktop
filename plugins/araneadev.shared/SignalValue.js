// Values received through a QML `var` signal parameter, made plain again.
// Since Qt 6.12 such a parameter arrives as a converted map: its keys are
// sorted and its arrays (or the value itself, when it is an array) are
// sequence objects that fail Array.isArray (array methods still work).
// A handler that inspects a payload's structure calls plain() first, and
// code comparing payloads uses same()/key(), which ignore key order. No
// QML, no I/O; tests/js/signal-value.test.js runs this under Node.

/**
 * Whether a value is a sequence object: indexed with a length, not an Array.
 * @param {*} v - any value
 * @returns {boolean} true for a Qt sequence (or an array-like stand-in)
 */
function isSequence(v) {
  if (!v || typeof v !== "object" || Array.isArray(v) || typeof v.length !== "number") return false
  return Object.keys(v).every(function (k) {
    return k === "length" || /^\d+$/.test(k)
  })
}

/**
 * Whether a value is plain data a payload copy may rebuild: a plain object
 * or a converted map ("[object V4ReferenceObject]"), not a QObject such as
 * an item, whose string form is "Type(0x...)".
 * @param {*} v - any value
 * @returns {boolean} true for a plain or converted map
 */
function isRecord(v) {
  return !!v && typeof v === "object" && !Array.isArray(v) && /^\[object \w+\]$/.test(String(v))
}

/**
 * A deep copy with real arrays in place of sequences. Scalars, QObjects and
 * other non-data values are kept as they are.
 * @param {*} v - a received signal value
 * @returns {*} the same data as plain JS
 */
function plain(v) {
  if (Array.isArray(v) || isSequence(v)) return Array.prototype.map.call(v, plain)
  if (!isRecord(v)) return v
  /** @type {{[key: string]: *}} */
  var out = {}
  Object.keys(v).forEach(function (k) {
    out[k] = plain(v[k])
  })
  return out
}

/**
 * One JSON string per value, with object keys sorted and sequences as arrays.
 * @param {*} v - any JSON-like value
 * @returns {string} canonical JSON
 */
function key(v) {
  return JSON.stringify(plain(v), function (k, x) {
    if (!isRecord(x)) return x
    /** @type {{[key: string]: *}} */
    var sorted = {}
    Object.keys(x)
      .sort()
      .forEach(function (name) {
        sorted[name] = x[name]
      })
    return sorted
  })
}

/**
 * Whether two values hold the same data, whatever their key order.
 * @param {*} a - one value
 * @param {*} b - the other value
 * @returns {boolean} true when equal as canonical JSON
 */
function same(a, b) {
  return key(a) === key(b)
}

if (typeof module !== "undefined")
  module.exports = {
    plain: plain,
    key: key,
    same: same
  }
