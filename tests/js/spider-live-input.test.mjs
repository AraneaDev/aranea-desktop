import assert from "node:assert/strict"
import { test } from "node:test"
import fs from "node:fs"
import vm from "node:vm"
const code = () =>
  fs.readFileSync(new URL("../../branding/3d/live/dismiss.js", import.meta.url), "utf8")
function documentFixture(dataset = {}) {
  return {
    body: { dataset },
    head: { append() {} },
    createElement: () => ({ textContent: "" }),
    getElementById: () => ({ textContent: "" })
  }
}
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
    document: documentFixture(),
    URLSearchParams,
    performance: { now: () => 0 },
    fetch: async (...args) => requests.push(args),
    MutationObserver: class {
      observe() {}
    },
    setTimeout: () => {}
  }
  vm.runInNewContext(code(), context)
  await events.keydown({ key: "Escape" })
  await events.pointerdown({})
  assert.equal(requests.length, 1)
  assert.equal(requests[0][1].headers["X-Aranea-Session"], "owned-token")
  assert.equal(closed, 1)
})

function harness(search = "?session=owned-token&screen=DP-1") {
  const events = {},
    requests = [],
    timers = []
  let observe
  const dataset = {}
  const context = {
    window: {
      location: { search },
      addEventListener: (type, fn) => (events[type] = fn),
      close: () => {}
    },
    document: documentFixture(dataset),
    URLSearchParams,
    performance: { now: () => 0 },
    fetch: async (...args) => requests.push(args),
    setTimeout: (fn) => timers.push(fn),
    MutationObserver: class {
      constructor(fn) {
        observe = fn
      }
      observe() {}
    }
  }
  vm.runInNewContext(code(), context)
  return { events, requests, timers, dataset, mutate: () => observe() }
}

test("ready is sent once only after the scene reports its first rendered frame", () => {
  const h = harness()
  assert.equal(h.requests.length, 0)
  h.dataset.phase = "walk"
  h.mutate()
  assert.equal(h.requests.length, 0)
  h.dataset.ready = "true"
  h.mutate()
  h.mutate()
  assert.equal(h.requests.length, 1)
  assert.equal(h.requests[0][0], "/__ready")
  assert.equal(h.requests[0][1].headers["X-Aranea-Session"], "owned-token")
  assert.deepEqual(JSON.parse(h.requests[0][1].body), { screenId: "DP-1" })
})

test("WebGL/module failure is reported once with bounded local text while input stays live", async () => {
  const h = harness()
  h.events.error({ message: "https://untrusted.example/" + "x".repeat(9000) })
  h.events.unhandledrejection({ reason: "remote detail" })
  h.timers[0]()
  await h.events.keydown({ key: "a" })
  assert.deepEqual(
    h.requests.map((request) => request[0]),
    ["/__failed", "/__dismiss"]
  )
  const failure = JSON.parse(h.requests[0][1].body)
  assert.equal(failure.screenId, "DP-1")
  assert.ok(failure.message.length < 512)
  assert.ok(!failure.message.includes("https:"))
  assert.deepEqual(JSON.parse(h.requests[1][1].body), { screenId: "DP-1" })
})
