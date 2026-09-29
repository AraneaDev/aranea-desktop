// Logic contract for the clipboard modules (moved from tests/clipboard.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const { test } = require("node:test")
const fs = require("fs")
const { loadPragma } = require("./lib/load-pragma.js")

const stock = "/usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js"
const c = loadPragma("plugins/araneadev.clipboard/ClipboardLogic.js")
const presentation = loadPragma("plugins/araneadev.clipboard/ClipboardPresentation.js")

test("clipboard presentation owns age formatting", () => {
  if (presentation.relativeAge(1000000000000 - 60000, 1000000000000) !== "1m")
    throw new Error("age formatting")
})

const assert = (cond, msg) => {
  if (!cond) throw new Error(msg)
}
const eq = (a, b, msg) => {
  if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
}

const now = 1000000000000
const MIN = 60000

test("detectKind recognises links, paths, colours, code, text and images", () => {
  const k = (t) => c.detectKind({ type: "text", text: t })
  assert(k("https://github.com/AraneaDev/aranea-desktop/pull/47") === "link", "link")
  assert(k("/home/tim/Work/file.txt") === "path" && k("~/notes.md\n/etc/hosts") === "path", "paths")
  assert(
    k("#7a5cff") === "colour" && k("rgb(59, 255, 158)") === "colour" && k("#abc") === "colour",
    "colours"
  )
  assert(
    k("if (x) {\n  y()\n}") === "code" &&
      k("$ git status") === "code" &&
      k("ls | wc -l") === "code",
    "code"
  )
  assert(k("hello world") === "text" && k("/not a path with spaces") === "text", "text")
  assert(
    c.detectKind({ type: "image", path: "/tmp/a.png", mime: "image/png" }) === "image",
    "image"
  )
})

test("isSecretText finds credential and token patterns (Review Focus 1)", () => {
  for (const s of [
    "ghp_0123456789abcdefghijABCDEFGHIJ0123",
    "github_pat_11ABCDEFG0123456789_abcdefghijklmnopqrstuvwxyz",
    "sk-proj-abcdefghijklmnopqrstuvwxyz012345",
    "xoxb-1234567890-abcdefghij",
    "AKIAABCDEFGHIJKLMNOP",
    "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjMifQ.abcDEF123_-x",
    "Marjonekke123!Q9",
    "Tr0ub4dor&3xK9#pQ",
    "-----BEGIN OPENSSH PRIVATE KEY-----\nabc\n-----END OPENSSH PRIVATE KEY-----"
  ]) {
    assert(c.isSecretText(s), "secret not detected: " + s.slice(0, 12))
  }
  for (const s of [
    "0123456789abcdef0123456789abcdef01234567",
    "a3f9c2e",
    "550e8400-e29b-41d4-a716-446655440000",
    "hello world this is fine",
    "https://example.com/a?b=c",
    "/usr/share/omarchy/bin",
    "Marjonekke",
    "short1!A"
  ]) {
    assert(!c.isSecretText(s), "false secret: " + s)
  }
})

test("enrich, override and normalizeEntry keep entry fields", () => {
  let e = c.enrich({ type: "text", text: "ghp_0123456789abcdefghijABCDEFGHIJ0123" }, now)
  assert(e.secret === true && e.kind === "text" && e.capturedAtMs === now, "enrich")
  e = c.enrich(
    { type: "text", text: "ghp_0123456789abcdefghijABCDEFGHIJ0123", secretOverride: false },
    now
  )
  assert(e.secret === false, "override wins")
  const kept = c.normalizeEntry({
    type: "text",
    text: "x",
    pinned: true,
    capturedAtMs: 5,
    kind: "text",
    secret: false,
    secretOverride: true
  })
  assert(
    kept.pinned === true && kept.capturedAtMs === 5 && kept.secretOverride === true,
    "normalize keeps fields"
  )
})

test("addEntry enforces the history limit, keeps pins and dedupes (Review Focus 2, 5)", () => {
  let h = []
  for (let i = 0; i < 305; i++) h = c.addEntry(h, { type: "text", text: "item " + i }, 300, now + i)
  assert(h.length === 300 && h[0].text === "item 304", "limit 300 newest first")
  h = c.togglePinned(h, 299)
  assert(h[299].pinned === true, "pin in place")
  for (let i = 0; i < 5; i++)
    h = c.addEntry(h, { type: "text", text: "more " + i }, 300, now + 400 + i)
  assert(
    h.some((x) => x.pinned && x.text === "item 5"),
    "pinned survives the limit"
  )
  assert(h.filter((x) => !x.pinned).length === 300, "limit counts unpinned only")
  h = c.addEntry(h, { type: "text", text: "item 5" }, 300, now + 999)
  assert(
    h[0].text === "item 5" &&
      h[0].pinned === true &&
      h.filter((x) => x.text === "item 5").length === 1,
    "re-copy keeps pin, dedupes"
  )
})

test("expire drops old unpinned secrets", () => {
  let s = [
    c.enrich({ type: "text", text: "ghp_0123456789abcdefghijABCDEFGHIJ0123" }, now - 11 * MIN),
    c.enrich(
      { type: "text", text: "sk-proj-abcdefghijklmnopqrstuvwxyz012345", pinned: true },
      now - 60 * MIN
    ),
    c.enrich({ type: "text", text: "plain old text" }, now - 600 * MIN),
    c.enrich({ type: "text", text: "AKIAABCDEFGHIJKLMNOP" }, now - 2 * MIN)
  ]
  let ex = c.expire(s, now, 10 * MIN)
  assert(
    ex.changed && ex.history.length === 3 && !ex.history.some((x) => x.text.startsWith("ghp_")),
    "old unpinned secret expires"
  )
  assert(
    ex.history.some((x) => x.pinned) && ex.history.some((x) => x.text === "plain old text"),
    "pinned and non-secrets stay"
  )
  assert(!c.expire(ex.history, now, 10 * MIN).changed, "nothing more to expire")
})

test("displayRows mask secrets, sort pinned first and support search", () => {
  const hist = [
    c.enrich({ type: "text", text: "https://github.com/AraneaDev" }, now - MIN),
    c.enrich({ type: "text", text: "ghp_0123456789abcdefghijABCDEFGHIJ0123" }, now - 3 * MIN),
    c.enrich({ type: "text", text: "#7a5cff", pinned: true }, now - 90 * MIN)
  ]
  const rows = c.displayRows(hist, "", 50, now)
  assert(
    rows[0].section === "pinned" && rows[0].historyIndex === 2 && rows[0].colour === "#7a5cff",
    "pinned first with its real index"
  )
  const sec = rows.find((r) => r.secret)
  assert(
    sec.historyIndex === 1 &&
      sec.title === "••••••••" &&
      sec.fullText === "" &&
      sec.detail === "secret · 3m",
    "secret masked with real index"
  )
  assert(!JSON.stringify(rows).includes("ghp_"), "secret text never in display rows")
  assert(c.displayRows(hist, "ghp", 50, now).length === 0, "search never matches secret content")
  assert(c.displayRows(hist, "secret", 50, now).length === 1, "secrets match the word secret")
  assert(
    rows.find((r) => r.kind === "link").title === "github.com/AraneaDev",
    "link title is domain + path"
  )
})

test("relativeAge formats durations", () => {
  assert(
    c.relativeAge(now - 30000, now) === "now" &&
      c.relativeAge(now - 3 * MIN, now) === "3m" &&
      c.relativeAge(now - 2 * 3600000, now) === "2h",
    "ages"
  )
})

test("stock compatibility: history round-trips with the stock parser (Review Focus 3)", () => {
  const stockRaw = JSON.stringify([
    { type: "text", text: "a" },
    { type: "image", path: "/tmp/x.png", mime: "image/png", capturedAt: "Sunday 10:00" }
  ])
  assert(c.parseHistory(stockRaw, now).length === 2, "stock-written history loads")
  if (fs.existsSync(stock)) {
    const sh = require(stock)
    const ours = JSON.stringify(
      c.parseHistory(stockRaw, now).map((x) => Object.assign(x, { pinned: true }))
    )
    assert(sh.parseHistory(ours).length === 2, "clone-written history loads in stock")
  } else {
    console.log("SKIP: stock Omarchy sources not present; parity checks not run")
  }
})

test("ordinary developer text is not flagged as a secret (final review I2)", () => {
  for (const s of [
    "src/components/Button.tsx",
    "AraneaDev/omarchy-aranea-theme",
    "Color.menu.selectedBackground",
    "ClipboardLogic.displayRows()",
    "ClipboardLogic.js:147",
    "Screenshot_2026-09-27_10-11-12.png",
    "v1.2.3-rc.1+build.5",
    "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    "Tim.Schipper@Example.com",
    "C:\\Users\\Tim\\Desktop"
  ]) {
    assert(!c.isSecretText(s), "developer text flagged as secret: " + s)
  }
})

test("real secrets are still detected next to developer text (final review I2)", () => {
  for (const s of [
    "Marjonekke123!Q9",
    "Tr0ub4dor&3xK9#pQ",
    "ghp_0123456789abcdefghijABCDEFGHIJ0123"
  ])
    assert(c.isSecretText(s), "lost secret " + s)
})

test("isSecretText recognises PGP private key blocks (final review m5)", () => {
  assert(
    c.isSecretText(
      "-----BEGIN PGP PRIVATE KEY BLOCK-----\nabc\n-----END PGP PRIVATE KEY BLOCK-----"
    ),
    "PGP private key"
  )
})

test("togglePinned keeps the most recently pinned entry first (final review I5)", () => {
  let ph = [
    c.enrich({ type: "text", text: "first" }, now - 3 * MIN),
    c.enrich({ type: "text", text: "second" }, now - 2 * MIN)
  ]
  ph = c.togglePinned(ph, 1, now - MIN) // pin "second" first
  ph = c.togglePinned(ph, 0, now) // then "first"
  const pr = c.displayRows(ph, "", 50, now).filter((r) => r.section === "pinned")
  assert(pr[0].historyIndex === 0 && pr[1].historyIndex === 1, "most recently pinned first")
  assert(c.togglePinned(ph, 0, now)[0].pinned === false, "unpin")
})

test("toggleSecret is a no-op for images (final review m1)", () => {
  const img = [c.enrich({ type: "image", path: "/tmp/a.png", mime: "image/png" }, now)]
  assert(
    c.toggleSecret(img, 0)[0].secret === false &&
      c.toggleSecret(img, 0)[0].secretOverride === undefined,
    "image secret toggle is a no-op"
  )
})

test("displayRows keeps kind and first line for a large code paste (final review m2)", () => {
  const big = "function f() {\n" + "  x()\n".repeat(3000) + "}"
  const bigRow = c.displayRows([c.enrich({ type: "text", text: big }, now)], "", 50, now)[0]
  assert(
    bigRow.kind === "code" && bigRow.title === "function f() {",
    "capped code keeps kind and first line"
  )
})

test("enrich reuses a stored kind instead of recomputing it (final review m3)", () => {
  assert(
    c.enrich({ type: "text", text: "plain words here", kind: "code" }, now).kind === "code",
    "stored kind reused"
  )
})

test("hadUnstamped reports history saved without a timestamp (final review m4)", () => {
  assert(c.hadUnstamped('[{"type":"text","text":"a"}]') === true, "unstamped detected")
  assert(
    c.hadUnstamped('[{"type":"text","text":"a","capturedAtMs":5}]') === false,
    "stamped history"
  )
})

test("secret detection (4a)", () => {
  for (const s of [
    "P@ssw0rd123456789",
    "x7Kp2mQ9vL4nR8sT",
    "aB3xQ9pL2mZ7kR4t",
    "dGhpcyBpcyBhIHNlY3JldA",
    "AIzaSyD-9tSrke72PouQMnMX-a7eZSW0jkFMBWY",
    "Xk9/pQ2mZ7vL4nR8",
    "Kq3:Zp9vL2mX7nR4w",
    "hunter2.Pr0d#2026"
  ])
    assert(c.isSecretText(s), "secret not detected: " + s)
  for (const s of [
    "getUserById2Async",
    "handleClick2Event",
    "useQueryClient3Hook",
    "AraneaDevOmarchyTheme2026",
    "ssh://git@github.com:22/x.git",
    "~/.config/omarchy/shell.json"
  ])
    assert(!c.isSecretText(s), "false secret: " + s)
  assert(c.wordShare("getUserById2Async") > 0.65, "identifier is word-like")
  assert(c.wordShare("x7Kp2mQ9vL4nR8sT") === 0, "random has no words")
  assert(c.isDeveloperText("Tim.Schipper@Example.com"), "email is developer text")
  assert(!c.isDeveloperText("P@ssw0rd123456789"), "leetspeak is not an email")
})

test("secrets cannot be opened (4a)", () => {
  if (c.canOpen({ secret: true }) !== false) throw new Error("secret opened")
  if (c.canOpen({ secret: false }) !== true) throw new Error("plain refused")
  if (c.canOpen(null) !== false) throw new Error("null opened")
})

test("unstamped entries are detected (4a)", () => {
  const t = (raw, want, msg) => {
    if (c.hadUnstamped(raw) !== want) throw new Error(msg)
  }
  t('[{"type":"text","text":"a","capturedAtMs":null}]', true, "null stamp")
  t('["plain string entry"]', true, "string entry")
  t('[{"type":"text","text":"a","capturedAtMs":"5"}]', true, "string stamp")
  t('[{"type":"text","text":"a","capturedAtMs":5}]', false, "stamped")
  t("not json", false, "invalid json")
})

test("secret expiry (4a)", () => {
  const TTL = 10 * MIN
  const s = (at, extra) =>
    Object.assign({ type: "text", text: "x", secret: true, capturedAtMs: at }, extra)
  eq(c.secretExpiryText(s(now - 3 * MIN), now, TTL), "expires in 7m", "minutes left")
  eq(c.secretExpiryText(s(now - TTL + 30000), now, TTL), "expires in <1m", "under a minute")
  eq(c.secretExpiryText(s(now - TTL - MIN), now, TTL), "expires in <1m", "overdue")
  eq(c.secretExpiryText(s(now, {}), now, 3 * 60 * MIN), "expires in 3h", "hours")
  eq(c.secretExpiryText(s(now, { pinned: true }), now, TTL), "", "pinned never expires")
  eq(c.secretExpiryText({ type: "text", text: "x", capturedAtMs: now }, now, TTL), "", "not secret")
  eq(c.secretExpiryText(null, now, TTL), "", "no entry")
  // Marking an old item secret restarts its clock, so it is not dropped at once
  const old = [c.enrich({ type: "text", text: "plain words", capturedAtMs: now - 60 * MIN }, now)]
  const marked = c.toggleSecret(old, 0, now)
  eq(marked[0].secret, true, "marked")
  eq(marked[0].capturedAtMs, now, "restamped")
  eq(c.expire(marked, now + MIN, TTL).changed, false, "kept after marking")
  eq(c.toggleSecret(marked, 0, now + MIN)[0].capturedAtMs, now, "unmarking keeps the stamp")
})

test("colour swatches (4a)", () => {
  eq(c.swatchColor("#7a5cff"), "#7a5cff", "rgb hex")
  eq(c.swatchColor("#ABC"), "#abc", "short hex")
  eq(c.swatchColor("#11223380"), "#80112233", "RRGGBBAA becomes AARRGGBB")
  eq(c.swatchColor("rgb(59, 255, 158)"), "#3bff9e", "rgb()")
  eq(c.swatchColor("rgb(100%, 0%, 50%)"), "#ff0080", "rgb percentages")
  eq(c.swatchColor("rgba(255, 0, 0, 0.5)"), "#80ff0000", "rgba alpha")
  eq(c.swatchColor("rgba(255, 0, 0, 0)"), "#00ff0000", "rgba alpha 0")
  eq(c.swatchColor("rgb(255 0 0 / 50%)"), "#80ff0000", "space syntax with alpha")
  eq(c.swatchColor("hsl(120, 100%, 50%)"), "#00ff00", "hsl()")
  eq(c.swatchColor("hsla(240deg, 100%, 50%, 1)"), "#0000ff", "hsla deg")
  eq(c.swatchColor("hsl(0, 0%, 100%)"), "#ffffff", "hsl white")
  eq(c.swatchColor("rgb(1, 2)"), "", "too few channels")
  eq(c.swatchColor("rgb(a, b, c)"), "", "not numbers")
  eq(c.swatchColor("red"), "", "names are not swatched")
  const rows = c.displayRows([c.enrich({ type: "text", text: "#11223380" }, 0)], "", 50, 0)
  eq(rows[0].colour, "#11223380", "row keeps the text")
  eq(rows[0].swatch, "#80112233", "row carries the Qt colour")
})

test("final review fixes (4a)", () => {
  // I1: random mixed case is not "word-like"
  for (const s of [
    "iBRM4eugfjt0LbuX",
    "VpsxyytpEFVl1jaj",
    "2iTldxBGKXwSqPHVVacp",
    "bJQBIaaMdal7RcsfLhvhDHxa"
  ])
    eq(c.isSecretText(s), true, "random token " + s)
  // I2: a dot is not enough to make a password a name or a file
  for (const s of [
    "Kx9Qm7Zp.aB3xQ9pL",
    "P4ssword.Secur1ty",
    "Qwerty123.Zxcvbn456",
    "aB3xQ9pL2mZ7kR4t.q",
    "kX9qM7zP2wL4.txt",
    "Kx9Qm7@Zp9Wq.aBcD"
  ])
    eq(c.isSecretText(s), true, "dotted password " + s)
  // m8: a random token that starts with / is not a path
  eq(c.isSecretText("/aB3xQ9pL2mZ7kR4tWq8/Zy5Nc1Vb6Hj2Gf9Ds4Kp"), true, "slash token")
  // ...while developer text with dots and slashes stays plain
  for (const s of [
    "/dev/disk/by-uuid/550e8400-e29b-41d4-a716-446655440000",
    "/etc/pam.d/polkit-1",
    "os.path.join",
    "mail.example.co.uk",
    "someone@yieldergroup.com",
    "docs/superpowers/specs/2026-09-27-design.md",
    "parseHTTPResponse2Async"
  ])
    eq(c.isSecretText(s), false, "developer text " + s)
  // m1: hsl follows CSS Color 4
  eq(c.swatchColor("hsl(120 100 50)"), "#00ff00", "space syntax unitless is %")
  eq(c.swatchColor("hsl(120, 50, 50)"), "", "legacy syntax needs %")
  eq(c.swatchColor("hsl(0.5turn, 100%, 50%)"), "", "unsupported hue unit")
})
