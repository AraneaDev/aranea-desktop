// Exercise the host's plugin layout mirror without a live layer-shell window.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const { test } = require("node:test")
const source = fs.readFileSync("plugins/araneadev.bar/Bar.qml", "utf8")
const body = source.match(
  /function syncPluginBarApiObjects\(api\) \{([\s\S]*?)\n {2}\}\n\n {2}\/\/ Ownership/
)[1]
const sync = new Function("root", "api", body)

test("click registry changes preserve an unchanged plugin layout", () => {
  let writes = 0
  let layout = { right: ["araneadev.tray"] }
  const api = {
    get layoutConfig() {
      return layout
    },
    set layoutConfig(value) {
      writes++
      layout = value
    }
  }
  const root = {
    activePopout: null,
    pluginOwnsBarObject: () => false,
    pluginClickTargets: () => [],
    publicLayoutConfig: () => ({ right: ["araneadev.tray"] })
  }
  sync(root, api)
  sync(root, api)
  assert.equal(writes, 0)
  root.publicLayoutConfig = () => ({ right: ["araneadev.tray", "omarchy.dropbox"] })
  sync(root, api)
  assert.equal(writes, 1)
  assert.deepEqual(layout.right, ["araneadev.tray", "omarchy.dropbox"])
})
