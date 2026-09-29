// The service bridges (HealthBridge.js, ServiceBridge.js): one published
// service per engine that only its own instance can retract, so a reloaded
// service that publishes before the old one goes stays published.
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const assert = require("node:assert/strict")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

const registry = loadPragma("plugins/araneadev.shared/ServiceRegistry.js")

test("shared service registry creates isolated publish slots", () => {
  const health = registry.create()
  const notifications = registry.create()
  const healthService = { name: "health" }
  const notificationService = { name: "notifications" }

  assert.equal(health.current(), null)
  assert.equal(notifications.current(), null)
  health.publish(healthService)
  notifications.publish(notificationService)
  assert.equal(health.current(), healthService)
  assert.equal(notifications.current(), notificationService)
  health.retract(notificationService)
  assert.equal(health.current(), healthService)
  health.retract(healthService)
  assert.equal(health.current(), null)
})

const bridges = [
  "plugins/araneadev.health/HealthBridge.js",
  "plugins/araneadev.notifications/ServiceBridge.js"
]

for (const file of bridges) {
  test(`${file}: nothing is published at first`, () => {
    assert.equal(loadPragma(file).current(), null)
  })

  test(`${file}: a published service is current`, () => {
    const bridge = loadPragma(file)
    const service = { name: "service" }
    bridge.publish(service)
    assert.equal(bridge.current(), service)
  })

  test(`${file}: publishing nothing clears the slot`, () => {
    const bridge = loadPragma(file)
    bridge.publish({})
    bridge.publish(undefined)
    assert.equal(bridge.current(), null)
  })

  test(`${file}: the old service going away after a reload leaves the new one`, () => {
    const bridge = loadPragma(file)
    const oldService = { name: "old" }
    const newService = { name: "new" }
    bridge.publish(oldService)
    bridge.publish(newService)
    bridge.retract(oldService)
    assert.equal(bridge.current(), newService)
  })

  test(`${file}: the current service retracting clears the slot`, () => {
    const bridge = loadPragma(file)
    const service = { name: "service" }
    bridge.publish(service)
    bridge.retract(service)
    assert.equal(bridge.current(), null)
  })
}
