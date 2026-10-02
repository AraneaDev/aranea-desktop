// Shared nmcli terse-output parsing, generated into
// `araneadev.network/NetworkLogic.js` and `araneadev.vpn/VpnLogic.js` by
// `tools/js-facade-generator.mjs` (see docs/development.md's "JavaScript
// facades") rather than imported or hand-copied, since no cross-`.js`-file
// import mechanism is usable from both QML and Node in this codebase. No
// QML, no I/O; tests/js/nmcli-terse.test.js runs this under Node.

/**
 * Splits one `nmcli -t` line into its fields, on unescaped `:` only, and
 * unescapes `\:` and `\\` within each field.
 * @param {string|undefined} line - one line of `nmcli -t` output
 * @returns {string[]} the line's fields, unescaped
 */
function splitTerse(line) {
  var s = String(line || "")
  var fields = []
  var cur = ""
  for (var i = 0; i < s.length; i++) {
    var c = s[i]
    if (c === "\\" && i + 1 < s.length && (s[i + 1] === ":" || s[i + 1] === "\\")) {
      cur += s[i + 1]
      i++
      continue
    }
    if (c === ":") {
      fields.push(cur)
      cur = ""
      continue
    }
    cur += c
  }
  fields.push(cur)
  return fields
}

if (typeof module !== "undefined") module.exports = { splitTerse: splitTerse }
