import assert from "node:assert/strict"
import { test } from "node:test"
import fs from "node:fs"
import vm from "node:vm"
const code = () =>
  fs.readFileSync(new URL("../../branding/3d/live/dismiss.js", import.meta.url), "utf8")
test("dismissal is independent of scene/WebGL loading and only happens once", async () => {
  const events = {},
    requests = []
  let closed = 0
  const window = {
    location: { search: "?session=owned-token" },
    addEventListener: (type, fn) => (events[type] = fn),
    close: () => closed++
  }
  const context = {
    window,
    document: { body: { dataset: {} }, getElementById: () => ({ textContent: "" }) },
    URLSearchParams,
    performance: { now: () => 0 },
    fetch: async (...args) => requests.push(args),
    setTimeout: () => {}
  }
  vm.runInNewContext(code(), context)
  await events.keydown({ key: "Escape" })
  await events.pointerdown({})
  assert.equal(requests.length, 1)
  assert.equal(requests[0][1].headers["X-Aranea-Session"], "owned-token")
  assert.equal(closed, 1)
})
