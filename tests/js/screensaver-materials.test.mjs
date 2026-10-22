import test from "node:test"
import assert from "node:assert/strict"
import { detailValue } from "../../branding/3d/collection/materials.mjs"

for (const kind of ["metal", "silk", "stone", "crystal"]) {
  test(`${kind} texture is deterministic, varied and seamless across repeated UVs`, () => {
    const shades = new Set()
    let seededDifferences = 0
    for (let y = 0; y < 17; y++)
      for (let x = 0; x < 17; x++) {
        const u = x / 16,
          v = y / 16,
          value = detailValue(kind, u, v, 7)
        assert.ok(Number.isFinite(value) && value >= 0 && value <= 1)
        assert.equal(value, detailValue(kind, u, v, 7))
        assert.ok(Math.abs(value - detailValue(kind, u + 3, v - 2, 7)) < 1e-10)
        shades.add(Math.round(value * 255))
        if (Math.abs(value - detailValue(kind, u, v, 19)) > 0.01) seededDifferences++
      }
    assert.ok(shades.size > 20, "surface contains visible tonal detail")
    assert.ok(seededDifferences > 100, "seed changes the material instead of repeating one stamp")
    for (let v = 0; v <= 1; v += 0.03125)
      assert.ok(Math.abs(detailValue(kind, 1 - 1e-7, v, 7) - detailValue(kind, 1e-7, v, 7)) < 0.001)
  })
}
test("unknown procedural materials fail explicitly", () => {
  assert.throws(() => detailValue("missing", 0.2, 0.3), RangeError)
})
