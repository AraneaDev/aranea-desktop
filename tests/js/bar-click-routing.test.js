// Exercise the bar's actual click router with clipped drawer scene geometry.
const assert = require("node:assert/strict")
const fs = require("node:fs")
const { test } = require("node:test")
const source = fs.readFileSync("plugins/araneadev.bar/Bar.qml", "utf8")
const body = source.slice(
  source.indexOf("  function moduleTargetClickable("),
  source.indexOf("  // Format a color")
)
const makeRouter = new Function("clickTargets", body + "\n return {moduleClickTargetAt};")

function scene(vertical, reveal) {
  const slot = {
    width: vertical ? 30 : 25 + reveal,
    height: vertical ? 25 + reveal : 30,
    parent: null
  }
  const clip = {
    parent: slot,
    clip: true,
    x: vertical ? 0 : 25,
    y: vertical ? 25 : 0,
    width: vertical ? 30 : reveal,
    height: vertical ? reveal : 30
  }
  const icon = {
    parent: clip,
    x: vertical ? 0 : reveal - 25,
    y: vertical ? reveal - 25 : 0,
    width: vertical ? 30 : 25,
    height: vertical ? 25 : 30,
    visible: true,
    triggerPress() {}
  }
  const arrow = {
    parent: slot,
    x: 0,
    y: 0,
    width: vertical ? 30 : 25,
    height: vertical ? 25 : 30,
    visible: true,
    triggerPress() {}
  }
  slot.mapToItem = (target, x, y) => {
    for (let current = target; current !== slot; current = current.parent) {
      x -= current.x || 0
      y -= current.y || 0
    }
    return { x, y }
  }
  const router = makeRouter([arrow, icon])
  return { slot, icon, arrow, router }
}

for (const vertical of [false, true]) {
  test(`collapsed ${vertical ? "vertical" : "horizontal"} drawer cannot steal chevron clicks`, () => {
    const { slot, arrow, router } = scene(vertical, 0)
    assert.equal(router.moduleClickTargetAt(slot, 12, 12), arrow)
  })
  test(`partly open ${vertical ? "vertical" : "horizontal"} drawer respects its clip`, () => {
    const { slot, arrow, icon, router } = scene(vertical, 10)
    assert.equal(router.moduleClickTargetAt(slot, 12, 12), arrow)
    assert.equal(router.moduleClickTargetAt(slot, vertical ? 12 : 30, vertical ? 30 : 12), icon)
  })
}
