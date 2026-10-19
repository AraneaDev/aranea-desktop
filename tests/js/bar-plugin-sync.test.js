// Exercise the host's plugin layout mirror without a live layer-shell window.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const { test } = require("node:test")
const source = fs.readFileSync("plugins/araneadev.bar/Bar.qml", "utf8")
/**
 * Extract a root-level QML function while retaining the real implementation.
 * @param {string} name - the QML function name
 * @returns {string} the function body
 */
function bodyOf(name) {
  return source.match(
    new RegExp(`function ${name}\\([^)]*\\)(?:: \\w+)? \\{([\\s\\S]*?)\\n {2}\\}`)
  )[1]
}
const sync = new Function("root", "api", "layoutSnapshot", bodyOf("syncPluginBarApiObjects"))

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
    layoutConfig: { right: ["araneadev.tray"] }
  }
  sync(root, api)
  sync(root, api)
  assert.equal(writes, 0)
  root.layoutConfig = { right: ["araneadev.tray", "omarchy.dropbox"] }
  sync(root, api)
  assert.equal(writes, 1)
  assert.deepEqual(layout.right, ["araneadev.tray", "omarchy.dropbox"])
})

test("a burst of click registrations queues one API refresh", () => {
  const pending = []
  const root = { syncAllPluginBarApiObjects() {} }
  const schedule = new Function(
    "root",
    "Qt",
    `let pluginBarApiSyncQueued = false; return function () {${bodyOf("schedulePluginBarApiSync")}}`
  )(root, { callLater: (callback) => pending.push(callback) })
  for (let i = 0; i < 500; i++) schedule()
  assert.deepEqual(pending, [root.syncAllPluginBarApiObjects])
})

test("a shared layout snapshot is detached for each plugin", () => {
  const root = {
    activePopout: null,
    pluginOwnsBarObject: () => false,
    pluginClickTargets: () => [],
    publicLayoutConfig: () => {
      throw new Error("must use the shared snapshot")
    }
  }
  const first = {}
  const second = {}
  const snapshot = JSON.stringify({ right: ["araneadev.tray"] })
  sync(root, first, snapshot)
  sync(root, second, snapshot)
  first.layoutConfig.right.push("foreign")
  assert.deepEqual(second.layoutConfig.right, ["araneadev.tray"])
})
