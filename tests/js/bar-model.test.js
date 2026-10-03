// Logic contract for the BarModel module (split from plugin-state.test.js).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

const root = path.join(__dirname, "..", "..")
const bar = require(`${root}/plugins/araneadev.bar/BarModel.js`)

test("bar model resolves a semantic color for every known state and falls back for unknown ones", () => {
  for (const state of [
    "healthy",
    "focus",
    "attention",
    "warning",
    "error",
    "muted",
    "charging",
    "privacy"
  ]) {
    if (!bar.semanticColor(state)) throw new Error(`missing semantic state: ${state}`)
  }
  if (bar.semanticColor("unknown") !== "dark_foreground")
    throw new Error("unknown state must be muted")
  if (bar.normalizePosition("left") !== "left") throw new Error("bar position normalization failed")
  if (bar.normalizePosition("diagonal") !== "top")
    throw new Error("invalid bar position must fall back to top")
})

test("bar model normalizeLayout fills in missing sections", () => {
  const normalizedLayout = bar.normalizeLayout({
    left: [{ id: "omarchy.clock" }],
    center: "invalid"
  })
  if (!Array.isArray(normalizedLayout.left) || normalizedLayout.left.length !== 1)
    throw new Error("left layout normalization failed")
  if (!Array.isArray(normalizedLayout.center) || normalizedLayout.center.length !== 0)
    throw new Error("center layout fallback failed")
  if (!Array.isArray(normalizedLayout.right) || normalizedLayout.right.length !== 0)
    throw new Error("right layout fallback failed")
})

test("bar model no longer filters modules by profile (4b)", () => {
  // 4b: no profile filtering; the bar shows every configured module
  for (const gone of ["normalizeProfile", "profileAllows", "filterProfile"])
    if (bar[gone] !== undefined) throw new Error("bar profile helper still exported: " + gone)
})

test("bar model barTransparent defaults to glass unless explicitly opaque (4b)", () => {
  // 4b: glass by default; only an explicit false gives the opaque bar
  if (bar.barTransparent({}) !== true) throw new Error("missing transparent must be glass")
  if (bar.barTransparent({ transparent: true }) !== true) throw new Error("true must be glass")
  if (bar.barTransparent({ transparent: false }) !== false) throw new Error("false must be opaque")
  if (bar.barTransparent(null) !== true) throw new Error("non-object config must be glass")
  if (bar.barTransparent({ transparent: "false" }) !== true)
    throw new Error("only the boolean false is opaque")
})

test("bar model layout helpers (4b)", () => {
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const layout = ["omarchy.a", { id: "omarchy.clock", format: "HH:mm" }, { id: "omarchy.b" }]
  eq(bar.entryId("omarchy.a"), "omarchy.a", "string id")
  eq(bar.entryId({ id: 7 }), "7", "object id")
  eq(bar.entryId({}), "", "no id")
  eq(bar.entrySettings({ id: "x", format: "y" }), { format: "y" }, "settings without id")
  eq(bar.moduleString(layout[1], "format", "?"), "HH:mm", "module string")
  eq(bar.moduleString(layout[1], "missing", "?"), "?", "module string fallback")
  eq(bar.entryIndex(layout, "omarchy.clock"), 1, "index")
  eq(bar.entriesBefore(layout, "omarchy.clock"), ["omarchy.a"], "before anchor")
  eq(bar.entriesAfter(layout, "omarchy.clock"), [{ id: "omarchy.b" }], "after anchor")
  eq(bar.entriesAfter(layout, "missing"), [], "after missing anchor")
  eq(
    bar.pinTrayToInner(["omarchy.tray", "a", "b"], "left"),
    ["a", "b", "omarchy.tray"],
    "tray inner on the left"
  )
  eq(bar.pinTrayToInner(["a", "omarchy.tray"], "right"), ["omarchy.tray", "a"], "tray inner right")
  eq(
    bar.pinTrayToInner(["a", { id: "araneadev.tray" }], "right"),
    [{ id: "araneadev.tray" }, "a"],
    "the Aranea tray clone leads the right section too"
  )
  eq(bar.expandPath("~/x", "/home/u"), "/home/u/x", "tilde")
  eq(bar.expandPath("$HOME/x", "/home/u"), "/home/u/x", "$HOME")
  eq(bar.customModuleSafeName("../evil"), false, "unsafe name")
  eq(bar.customModuleType({ id: "x", exec: "date" }), "command", "command module")
  eq(bar.customModuleType({ id: "x", source: "a.qml" }), "qml", "qml module")
  eq(
    bar.customModulePath({ id: "clock2" }, "/h", "/c"),
    "/c/bar/modules/clock2.qml",
    "default path"
  )
  eq(bar.isDrawnSlot({ visible: true, width: 2, height: 2 }), true, "drawn slot")
  eq(bar.isDrawnSlot({ visible: false, width: 2, height: 2 }), false, "hidden slot")
})
