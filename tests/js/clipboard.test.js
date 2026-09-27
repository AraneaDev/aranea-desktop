// Logic contract for the clipboard modules (moved from tests/clipboard.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

test("clipboard logic", () => {
  const root = path.join(__dirname, "..", "..")
  const stock = "/usr/share/omarchy/shell/plugins/clipboard/ClipboardHistory.js"
  const fs = require("fs")
  const c = require(`${root}/plugins/araneadev.clipboard/ClipboardLogic.js`)
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg)
  }
  const now = 1000000000000
  const MIN = 60000

  // --- kinds
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

  // --- secrets (Review Focus 1)
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

  // --- enrich / override / normalise keeps fields
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

  // --- history: add, limit, pins, indexes (Review Focus 2, 5)
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

  // --- expiry
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

  // --- display rows: masking, sections, real indexes, search
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

  // --- ages
  assert(
    c.relativeAge(now - 30000, now) === "now" &&
      c.relativeAge(now - 3 * MIN, now) === "3m" &&
      c.relativeAge(now - 2 * 3600000, now) === "2h",
    "ages"
  )

  // --- stock compatibility (Review Focus 3)
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

  // --- final-review fixes
  // I2: ordinary developer text is not a secret (paths, identifiers, emails, versions)
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
  // ...while real secrets still are (pattern tokens and random passwords)
  for (const s of [
    "Marjonekke123!Q9",
    "Tr0ub4dor&3xK9#pQ",
    "ghp_0123456789abcdefghijABCDEFGHIJ0123"
  ])
    assert(c.isSecretText(s), "lost secret " + s)
  // m5: PGP private key blocks
  assert(
    c.isSecretText(
      "-----BEGIN PGP PRIVATE KEY BLOCK-----\nabc\n-----END PGP PRIVATE KEY BLOCK-----"
    ),
    "PGP private key"
  )

  // I5: PINNED is most recently pinned first
  let ph = [
    c.enrich({ type: "text", text: "first" }, now - 3 * MIN),
    c.enrich({ type: "text", text: "second" }, now - 2 * MIN)
  ]
  ph = c.togglePinned(ph, 1, now - MIN) // pin "second" first
  ph = c.togglePinned(ph, 0, now) // then "first"
  const pr = c.displayRows(ph, "", 50, now).filter((r) => r.section === "pinned")
  assert(pr[0].historyIndex === 0 && pr[1].historyIndex === 1, "most recently pinned first")
  assert(c.togglePinned(ph, 0, now)[0].pinned === false, "unpin")

  // m1: images can't be marked secret
  const img = [c.enrich({ type: "image", path: "/tmp/a.png", mime: "image/png" }, now)]
  assert(
    c.toggleSecret(img, 0)[0].secret === false &&
      c.toggleSecret(img, 0)[0].secretOverride === undefined,
    "image secret toggle is a no-op"
  )

  // m2: a large code paste keeps its kind in the row title
  const big = "function f() {\n" + "  x()\n".repeat(3000) + "}"
  const bigRow = c.displayRows([c.enrich({ type: "text", text: big }, now)], "", 50, now)[0]
  assert(
    bigRow.kind === "code" && bigRow.title === "function f() {",
    "capped code keeps kind and first line"
  )

  // m3: stored kind is reused, not recomputed
  assert(
    c.enrich({ type: "text", text: "plain words here", kind: "code" }, now).kind === "code",
    "stored kind reused"
  )

  // m4: stock entries without a timestamp are reported so they get saved once
  assert(c.hadUnstamped('[{"type":"text","text":"a"}]') === true, "unstamped detected")
  assert(
    c.hadUnstamped('[{"type":"text","text":"a","capturedAtMs":5}]') === false,
    "stamped history"
  )

  console.log("clipboard logic contract passed")
})

test("secret detection (4a)", () => {
  const root = path.join(__dirname, "..", "..")
  const c = require(`${root}/plugins/araneadev.clipboard/ClipboardLogic.js`)
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg)
  }
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
  const c = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.clipboard/ClipboardLogic.js")
  )
  if (c.canOpen({ secret: true }) !== false) throw new Error("secret opened")
  if (c.canOpen({ secret: false }) !== true) throw new Error("plain refused")
  if (c.canOpen(null) !== false) throw new Error("null opened")
})
