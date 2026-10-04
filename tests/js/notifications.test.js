// Logic contract for the notifications modules (moved from tests/notifications.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")
const { loadPragma } = require("./lib/load-pragma.js")

test("notifications logic", () => {
  const root = path.join(__dirname, "..", "..")
  const inbox = require(`${root}/plugins/araneadev.notifications/InboxLogic.js`)
  const assert = (cond, msg) => {
    if (!cond) throw new Error(msg)
  }
  const DAY = 24 * 60 * 60 * 1000

  // --- store decision (spec §1 lifecycle, last row)
  assert(inbox.shouldStore(false, 1, false) === true, "normal app/normal urgency must be stored")
  assert(
    inbox.shouldStore(true, 0, false) === false,
    "ephemeral low-urgency sender must not be stored"
  )
  assert(
    inbox.shouldStore(true, 1, false) === true,
    "ephemeral sender at normal urgency must be stored"
  )
  assert(
    inbox.shouldStore(true, 2, false) === true,
    "ephemeral sender at critical urgency must be stored"
  )
  assert(inbox.shouldStore(false, 1, true) === false, "transient hint must never be stored")

  // --- pruning
  const now = 1000 * DAY
  const e = (name, ageDays, urgency) => ({
    fileName: name,
    timestamp: now - ageDays * DAY,
    urgency: urgency
  })
  let pruned = inbox.pruneInbox([e("old", 8, 1), e("oldCrit", 8, 2), e("fresh", 1, 1)], now)
  assert(pruned.drop.map((x) => x.fileName).join() === "old", "only non-critical entries age out")
  assert(pruned.keep.map((x) => x.fileName).join() === "fresh,oldCrit", "keep must be newest-first")

  const many = []
  for (let i = 0; i < 103; i++)
    many.push({
      fileName: "n" + i,
      timestamp: now - i * 1000,
      urgency: i === 102 ? 2 : 1
    })
  pruned = inbox.pruneInbox(many, now)
  assert(pruned.keep.length === 100, "cap must hold 100 entries")
  assert(
    pruned.keep.some((x) => x.fileName === "n102"),
    "oldest critical must survive while non-critical can go"
  )
  assert(
    pruned.drop
      .map((x) => x.fileName)
      .sort()
      .join() === "n100,n101,n99",
    "oldest non-critical dropped first"
  )

  const crits = []
  for (let i = 0; i < 101; i++)
    crits.push({ fileName: "c" + i, timestamp: now - i * 1000, urgency: 2 })
  pruned = inbox.pruneInbox(crits, now)
  assert(
    pruned.keep.length === 100 && pruned.drop[0].fileName === "c100",
    "criticals capped only when nothing else is left"
  )

  // --- swipe (Review Focus 4)
  assert(inbox.swipeOutcome(140, 380, 0) === "dismiss", "37% distance dismisses")
  assert(inbox.swipeOutcome(100, 380, 0) === "restore", "26% distance springs back")
  assert(inbox.swipeOutcome(30, 380, 1200) === "dismiss", "fast rightward flick dismisses")
  assert(inbox.swipeOutcome(-200, 380, -2000) === "restore", "leftward drag never dismisses")
  assert(
    inbox.suppressesClick(5) === true && inbox.suppressesClick(-5) === true,
    "drag beyond 4px suppresses click"
  )
  assert(inbox.suppressesClick(3) === false, "tiny jitter still clicks")

  // --- groups
  const g = (app, t) => ({ app: app, timestamp: t, fileName: app + t })
  const groups = inbox.groupView([g("Slack", 9), g("Build", 8), g("Slack", 7), g("Slack", 6)], {})
  assert(
    groups.length === 2 && groups[0].app === "Slack" && groups[1].app === "Build",
    "groups ordered by newest entry"
  )
  assert(
    groups[0].collapsed === true && groups[0].visible.length === 1 && groups[0].hidden === 2,
    "group of 3 starts collapsed"
  )
  assert(groups[1].collapsed === false && groups[1].hidden === 0, "small group starts expanded")
  const opened = inbox.groupView([g("Slack", 9), g("Slack", 7), g("Slack", 6)], { Slack: true })
  assert(opened[0].collapsed === false && opened[0].visible.length === 3, "explicit expand wins")
  const flat = inbox.flattenGroups(groups)
  assert(
    flat.map((r) => r.kind).join() === "group,entry,more,group,entry",
    "flattened rows follow group layout"
  )

  // --- labels
  assert(
    inbox.badgeLabel(0) === "" && inbox.badgeLabel(9) === "9" && inbox.badgeLabel(10) === "9+",
    "badge labels"
  )
  assert(inbox.tooltipText(1, 0, false, false) === "1 notification · DND off", "singular tooltip")
  assert(
    inbox.tooltipText(4, 0, true, false) === "4 notifications · DND on",
    "plural tooltip with DND"
  )
  assert(
    inbox.tooltipText(0, 0, false, true) === "0 notifications · Quiet hours",
    "quiet-hours tooltip"
  )
  assert(
    inbox.bellGlyph(false) === String.fromCodePoint(0xf009a) &&
      inbox.bellGlyph(true) === String.fromCodePoint(0xf009b),
    "bell glyphs"
  )
  assert(inbox.centerCaption(3, false, "07:00") === "3 unread", "unread count when not quiet")
  assert(inbox.centerCaption(0, false, "") === "Nothing new", "nothing new at 0")
  assert(inbox.centerCaption(3, true, "07:00") === "Quiet until 07:00", "quiet hours win")
  assert(inbox.centerCaption(0, true, "07:00") === "Quiet until 07:00", "quiet hours win at 0 too")
  assert(
    inbox.centerCaption(2, true, "") === "2 unread",
    "a malformed window falls back to the count"
  )
  assert(inbox.centerCaption(undefined, false, "") === "Nothing new", "a missing count reads as 0")
  assert(
    inbox.centerKeyHint(4) === "↑↓ move · enter open · x dismiss · ⇧del group",
    "the full hint with entries"
  )
  assert(inbox.centerKeyHint(0) === "↑↓ move · enter toggle", "the short hint when empty")
  assert(
    inbox.centerKeyHint(undefined) === "↑↓ move · enter toggle",
    "a missing count reads as empty"
  )
  assert(inbox.listHeight(200, 400, 100, 60) === 200, "a short list keeps its content height")
  assert(inbox.listHeight(900, 400, 100, 60) === 240, "a long list is capped above the footer")
  assert(inbox.listHeight(900, 100, 80, 60) === 0, "never below 0")
  assert(inbox.listHeight(undefined, "x", null, NaN) === 0, "bad input reads as 0")
  assert(
    inbox.needsClearConfirm(20) === false && inbox.needsClearConfirm(21) === true,
    "confirm above 20"
  )
  assert(
    inbox.quietUntil("22:00-07:00") === "07:00" && inbox.quietUntil("bogus") === "",
    "quiet-until label"
  )
  assert(inbox.relativeTime(now - 30000, now) === "now", "under a minute")
  assert(inbox.relativeTime(now - 2 * 60000, now) === "2m", "minutes")
  assert(inbox.relativeTime(now - 3 * 3600000, now) === "3h", "hours")
  assert(inbox.relativeTime(now - 2 * DAY, now) === "2d", "days")

  const logic = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  assert(typeof logic.historyRows === "undefined", "history replay helper must be gone")

  // --- service bridge: the Aranea bar hands widgets a service-less facade, so
  // the panel finds its own plugin's service through a shared library module.
  const bridgeSrc = require("fs").readFileSync(
    `${root}/plugins/araneadev.notifications/ServiceBridge.js`,
    "utf8"
  )
  assert(bridgeSrc.startsWith(".pragma library"), "bridge must be a shared library module")
  assert(
    bridgeSrc.includes("@aranea-facade-start: plugins/araneadev.shared/ServiceRegistry.js"),
    "bridge must use the generated registry facade"
  )
  const bridge = loadPragma("plugins/araneadev.notifications/ServiceBridge.js")
  const svcA = { name: "a" },
    svcB = { name: "b" }
  assert(bridge.current() === null, "no service before publish")
  bridge.publish(svcA)
  assert(bridge.current() === svcA, "published service is current")
  bridge.publish(svcB)
  bridge.retract(svcA)
  assert(bridge.current() === svcB, "retracting a stale service keeps the newer one")
  bridge.retract(svcB)
  assert(bridge.current() === null, "retracting the current service clears it")

  // --- bell-only badge (Revision 1)
  let b = inbox.badgeState(0, 0, false)
  assert(b.tone === "none" && b.label === "", "empty inbox has no badge")
  b = inbox.badgeState(7, 0, false)
  assert(b.tone === "normal" && b.label === "7", "normal badge shows total")
  b = inbox.badgeState(7, 2, false)
  assert(b.tone === "critical" && b.label === "2", "critical badge shows critical count")
  b = inbox.badgeState(12, 11, true)
  assert(b.tone === "critical" && b.label === "9+", "critical shows through DND, capped")
  b = inbox.badgeState(5, 0, true)
  assert(b.tone === "none", "DND hides the normal badge")
  assert(
    inbox.tooltipText(7, 2, false, false) === "7 notifications · 2 critical · DND off",
    "tooltip with critical"
  )
  assert(
    inbox.tooltipText(1, 0, true, false) === "1 notification · DND on",
    "tooltip without critical"
  )
  const sorted = inbox.sortForCenter([
    { fileName: "a", timestamp: 3, urgency: 1 },
    { fileName: "b", timestamp: 1, urgency: 2 },
    { fileName: "c", timestamp: 2, urgency: 1 }
  ])
  assert(sorted.map((x) => x.fileName).join() === "b,a,c", "critical first, then newest")
  // --- snapshot: plain copies of exactly the row fields
  const liveRow = { fileName: "x.json", app: "mail", urgency: 2, timestamp: 5, extra: "no" }
  const snap = inbox.snapshotOf([liveRow, null])
  assert(snap.length === 2 && snap[0] !== liveRow, "snapshotOf copies every row")
  assert(
    Object.keys(snap[0]).join() === inbox.ROW_FIELDS.join(),
    "a copy holds the row fields only"
  )
  assert(snap[0].app === "mail" && snap[1].fileName === undefined, "copied values, null rows empty")
  liveRow.app = "changed"
  assert(snap[0].app === "mail", "a copy does not follow its source")
  assert(inbox.snapshotOf(undefined).length === 0, "no rows, empty snapshot")
  assert(
    inbox.criticalCount([{ urgency: 2 }, { urgency: "2" }, { urgency: 1 }, null]) === 2,
    "critical count"
  )
  assert(inbox.criticalCount(null) === 0, "no entries, no critical")
  const center = inbox.centerRows(sorted.slice().reverse(), {})
  assert(
    center.map((r) => r.kind + ":" + (r.entry ? r.entry.fileName : r.app)).join() ===
      "group:unknown,entry:b,more:unknown",
    "centerRows sorts, groups and flattens"
  )
  // --- centerRows parity with the pipeline it replaced, for collapsed
  // groups and "+N more" rows (more than COLLAPSE_AT entries per app)
  const crowded = []
  for (let i = 0; i < inbox.COLLAPSE_AT + 2; i++)
    crowded.push({ fileName: "chat" + i, app: "Chat", timestamp: 100 - i, urgency: 1 })
  for (let i = 0; i < inbox.COLLAPSE_AT; i++)
    crowded.push({ fileName: "mail" + i, app: "Mail", timestamp: 50 - i, urgency: i === 0 ? 2 : 1 })
  crowded.push({ fileName: "solo", app: "Build", timestamp: 75, urgency: 1 })
  for (const expanded of [{}, { Chat: true }, { Mail: true, Build: false }]) {
    const piped = inbox.flattenGroups(inbox.groupView(inbox.sortForCenter(crowded), expanded))
    assert(
      JSON.stringify(inbox.centerRows(crowded, expanded)) === JSON.stringify(piped),
      "centerRows matches sortForCenter, groupView and flattenGroups for " +
        JSON.stringify(expanded)
    )
  }
  const collapsedRows = inbox.centerRows(crowded, {})
  assert(
    collapsedRows.map(inbox.rowKey).join() ===
      "g:Mail,e:mail0,m:Mail,g:Chat,e:chat0,m:Chat,g:Build,e:solo",
    "collapsed groups show their newest entry and a +N more row"
  )
  assert(
    collapsedRows[2].hidden === inbox.COLLAPSE_AT - 1 &&
      collapsedRows[5].hidden === inbox.COLLAPSE_AT + 1 &&
      collapsedRows[0].collapsed &&
      !collapsedRows[6].collapsed,
    "the +N more counts and collapsed flags"
  )
  assert(
    inbox
      .centerRows(crowded, { Chat: true })
      .filter((r) => r.app === "Chat")
      .map((r) => r.kind)
      .join() === "group,entry,entry,entry,entry,entry",
    "an expanded group drops its +N more row"
  )
  // --- cursor follows the item (Important #5)
  const before = inbox.flattenGroups(inbox.groupView([g("Build", 8)], {}))
  const key = inbox.rowKey(before[1])
  const after = inbox.flattenGroups(inbox.groupView([g("Slack", 9), g("Build", 8)], {}))
  assert(
    inbox.indexOfKey(after, key) === 3,
    "cursor key re-resolves after a new group arrives on top"
  )
  assert(inbox.indexOfKey(after, "e:gone") === -1, "missing key resolves to -1")
  assert(typeof inbox.stackSplit === "undefined", "toast stack rules are gone")

  // --- sourceKey (system health items)
  const keyed = logic.parsePopupFiles(
    logic.serializePopup({ id: 0, originalId: 0, timestamp: 9, sourceKey: "disk:/" }, 1),
    1
  )
  assert(
    keyed.length === 1 && keyed[0].sourceKey === "disk:/",
    "sourceKey must survive serialize/parse"
  )
  assert(
    logic.popupEntry({ id: 1, timestamp: 1 }, 1).sourceKey === "",
    "ordinary entries carry an empty sourceKey"
  )
  // Health items no longer exist in the center: pruning treats every entry alike.
  const oldHealth = inbox.pruneInbox(
    [{ fileName: "h", timestamp: now - 30 * DAY, urgency: 1, sourceKey: "reboot" }],
    now
  )
  assert(oldHealth.drop.length === 1, "no pruning exemption for leftover health items")

  console.log("inbox logic contract passed")
})

test("toast holds (4c)", () => {
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const a = n.holdPopup({}, "5-1", true)
  eq(a, { "5-1": 1 }, "first hold")
  const b = n.holdPopup(a, "5-1", true)
  eq(b, { "5-1": 2 }, "second screen holds too")
  eq(a, { "5-1": 1 }, "input not mutated")
  eq(n.holdPopup(b, "5-1", false), { "5-1": 1 }, "one screen lets go")
  eq(n.holdPopup({ "5-1": 1 }, "5-1", false), {}, "last hold removes the key")
  eq(n.holdPopup({}, "5-1", false), {}, "never negative")
})

test("inbox consistency (4c)", () => {
  const root = path.join(__dirname, "..", "..", "plugins/araneadev.notifications")
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const inbox = require(`${root}/InboxLogic.js`)
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const now = 1000000
  eq(n.clampTimestamp(now + 5000, now), now, "future capped")
  eq(n.clampTimestamp(now - 5, now), now - 5, "past kept")
  eq(n.clampTimestamp("x", now), 0, "junk is 0")
  const disk = [
    { fileName: "a", timestamp: 3 },
    { fileName: "b", timestamp: 1 }
  ]
  const live = [{ fileName: "c", timestamp: 2 }]
  eq(
    inbox.mergeLoaded(disk, live, {}, false).map((r) => r.fileName),
    ["a", "c", "b"],
    "merge"
  )
  eq(
    inbox.mergeLoaded(disk, live, { a: true }, false).map((r) => r.fileName),
    ["c", "b"],
    "removed during load"
  )
  eq(
    inbox.mergeLoaded(disk, live, {}, true).map((r) => r.fileName),
    ["c"],
    "cleared during load keeps later arrivals"
  )
  eq(
    inbox.mergeLoaded(disk, [{ fileName: "a", timestamp: 3 }], {}, false).length,
    2,
    "live copy of a disk row is not doubled"
  )
})

test("dismiss actions (4c)", () => {
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )
  const eq = (a, b, msg) => {
    if (a !== b) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  eq(inbox.dismissAction({ kind: "more", app: "x" }, false), "expand", "Delete on +N more expands")
  eq(
    inbox.dismissAction({ kind: "more", app: "x" }, true),
    "group",
    "Shift+Delete clears the group"
  )
  eq(inbox.dismissAction({ kind: "entry" }, false), "dismiss", "entry")
  eq(
    inbox.dismissAction({ kind: "entry" }, true),
    "group",
    "Shift+Delete on an entry clears its group"
  )
  eq(inbox.dismissAction({ kind: "group" }, false), "group", "group header")
  eq(inbox.dismissAction(null, false), "", "no row")
})

test("notification dead code stays gone (4c)", () => {
  const root = path.join(__dirname, "..", "..", "plugins/araneadev.notifications")
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const inbox = require(`${root}/InboxLogic.js`)
  for (const gone of ["popupExpired", "groupNotifications", "collapseQuietHours", "limitHistory"])
    if (n[gone] !== undefined) throw new Error("dead helper still exported: " + gone)
  for (const gone of ["removesFromInbox", "upsertOrder"])
    if (inbox[gone] !== undefined) throw new Error("dead helper still exported: " + gone)
  const e = n.popupEntry({ id: 1, originalId: 1, timestamp: 5, onScreen: true, deadline: 9 }, 1)
  if ("onScreen" in e || "deadline" in e)
    throw new Error("popupEntry still carries onScreen/deadline")
})

test("body sanitizing, argv and image persistence (4c)", () => {
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  // image tags never reach StyledText (they could load local files)
  eq(
    n.styledBody("a<img src=x>b<b>c</b><IMG\nsrc=y>d", "app", ""),
    "ab<b>c</b>d",
    "img tags stripped"
  )
  eq(n.styledBody("x<img src=", "app", ""), "x", "unterminated img tag stripped")
  eq(n.styledBody("line1\nline2\r\nline3", "app", ""), "line1<br/>line2<br/>line3", "line breaks")
  // Chromium prefixes bodies with the site; only its own notifications lose it
  eq(
    n.sanitizeBody('<a href="https://example.com">example.com</a> Hello', "Google Chrome", ""),
    "Hello",
    "chromium link"
  )
  eq(n.sanitizeBody("www.example.com Hello there", "chromium", ""), "Hello there", "chromium host")
  eq(
    n.sanitizeBody("www.example.com Hello there", "Slack", ""),
    "www.example.com Hello there",
    "others untouched"
  )
  // click commands are argv vectors of strings, never flags first
  eq(n.parseExecArgv('["omarchy-launch","x"]'), ["omarchy-launch", "x"], "argv")
  for (const bad of ['["-rf"]', '["a",1]', "rm -rf", "[]", ""])
    eq(n.parseExecArgv(bad), null, "rejects " + bad)
  // images are copied into the state dir; image:// cannot be copied
  eq(
    n.persistablePopup(
      { timestamp: 5, originalId: 3, image: "/tmp/a.png", appIcon: "image://icon/x" },
      "/S/images/"
    ),
    {
      entry: { timestamp: 5, originalId: 3, image: "file:///S/images/5-3-image", appIcon: "" },
      copies: [{ from: "/tmp/a.png", to: "/S/images/5-3-image" }]
    },
    "persist"
  )
  eq(
    n.persistablePopup(
      { timestamp: 5, originalId: 3, image: "file:///S/images/5-3-image" },
      "/S/images/"
    ).copies,
    [],
    "an already persisted image is not copied onto itself"
  )
  eq(n.parseSettings('{"version":3,"dnd":true}').dnd, true, "settings")
  eq(n.parseSettings("{").error, true, "broken settings")
})

test("center images after a write (4c final review)", () => {
  const n = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")
  const eq = (a, b, msg) => {
    if (JSON.stringify(a) !== JSON.stringify(b)) throw new Error(`${msg}: got ${JSON.stringify(a)}`)
  }
  const live = { image: "image://qsimage/42", appIcon: "/tmp/.org.chromium/icon.png" }
  const record = { image: "", appIcon: "file:///S/images/5-3-appIcon" }
  // image:// cannot be copied: the live avatar stays while the sender lives
  eq(
    n.shownImages(record, live, ["/S/images/5-3-appIcon"]),
    { appIcon: "file:///S/images/5-3-appIcon", image: "image://qsimage/42" },
    "copied roles switch, others stay live"
  )
  // a refused copy (too big, FIFO, source gone) keeps the live value
  eq(
    n.shownImages(record, live, []),
    { appIcon: "/tmp/.org.chromium/icon.png", image: "image://qsimage/42" },
    "failed copy keeps the live path"
  )
})

test("NotificationLogic normalizes malformed notification fields and stabilizes malformed snapshots", () => {
  const notifications = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")

  const normalized = notifications.normalizeNotification({
    id: "not-a-number",
    appName: null,
    summary: 42,
    body: null,
    urgency: 99,
    expireTimeout: "not-a-number",
    hints: null
  })
  if (normalized.id !== 0 || normalized.appName !== "" || normalized.summary !== "42")
    throw new Error("notification fields were not normalized")
  if (normalized.urgency !== 1 || normalized.expireTimeout !== 0)
    throw new Error("invalid notification values were not defaulted")
  if (!normalized.hints || typeof normalized.hints !== "object")
    throw new Error("notification hints were not normalized")

  const malformedSnapshot = notifications.snapshotOf({ urgency: -1, hints: null }, "invalid")
  if (
    malformedSnapshot.urgency !== 1 ||
    typeof malformedSnapshot.timestamp !== "number" ||
    !Number.isFinite(malformedSnapshot.timestamp)
  ) {
    throw new Error("malformed notification snapshot was not stabilized")
  }
})

test("NotificationLogic isWithinQuietHours handles the overnight window", () => {
  const notifications = loadPragma("plugins/araneadev.notifications/NotificationLogic.js")

  const late = new Date(2026, 8, 22, 23, 15)
  const early = new Date(2026, 8, 23, 6, 45)
  const day = new Date(2026, 8, 22, 12, 0)
  if (!notifications.isWithinQuietHours("22:00-07:00", late))
    throw new Error("quiet hours missed late window")
  if (!notifications.isWithinQuietHours("22:00-07:00", early))
    throw new Error("quiet hours missed overnight window")
  if (notifications.isWithinQuietHours("22:00-07:00", day))
    throw new Error("quiet hours captured daytime")
})

test("notification center cursor stops", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )
  const entry = (name) => ({ kind: "entry", app: "A", entry: { fileName: name } })
  const rows = [{ kind: "group", app: "A" }, entry("a1"), { kind: "more", app: "A" }, entry("b1")]
  const stops = inbox.centerStops(rows, true)
  assert.deepEqual(
    stops.map((s) => s.key),
    ["dnd", "e:a1", "m:A", "e:b1", "clear"],
    "DND, entries and more rows (no group headers), then Clear"
  )
  assert.deepEqual(stops[1], { key: "e:a1", section: "rows", index: 1 })
  assert.deepEqual(stops[0], { key: "dnd", section: "dnd", index: -1 })
  assert.deepEqual(
    inbox.centerStops(rows, false).map((s) => s.key),
    ["dnd", "e:a1", "m:A", "e:b1"],
    "no Clear stop while the pill is hidden"
  )
  assert.deepEqual(
    inbox.centerStops(undefined, false).map((s) => s.key),
    ["dnd"]
  )
  assert.deepEqual(
    inbox.centerStops([null, entry("x")], false).map((s) => s.key),
    ["dnd", "e:x"]
  )

  assert.equal(inbox.stopIndex(stops, "e:b1"), 3)
  assert.equal(inbox.stopIndex(stops, "e:gone"), -1)
  assert.equal(inbox.stopIndex(stops, ""), -1)
  assert.equal(inbox.stopIndex(null, "dnd"), -1)

  assert.deepEqual(inbox.followStop(stops, "e:b1", true), { key: "e:b1", shown: true })
  assert.deepEqual(inbox.followStop(stops, "e:b1", false), { key: "e:b1", shown: false })
  assert.deepEqual(
    inbox.followStop(stops, "e:gone", true),
    { key: "", shown: false },
    "a vanished key is dropped and the cursor hides"
  )
  assert.deepEqual(inbox.followStop(stops, "", true), { key: "", shown: false })
  // The same key returning later finds no cursor: it was dropped.
  const gone = inbox.followStop(inbox.centerStops([], true), "e:a1", true)
  assert.deepEqual(inbox.followStop(stops, gone.key, gone.shown), { key: "", shown: false })
  assert.equal(inbox.revealStop(stops, -1), 1, "first reveal lands on the first row")
  assert.equal(inbox.revealStop(stops, 2), 2, "a vanished cursor reveals where it was")
  assert.equal(inbox.revealStop(stops, 9), 4, "clamped into the stops")
  assert.equal(
    inbox.revealStop(inbox.centerStops([], false), -1),
    0,
    "empty center: the DND switch"
  )
  assert.equal(inbox.revealStop([], -1), -1)
  assert.equal(inbox.revealStop(undefined, 0), -1)

  assert.equal(inbox.moveStop(stops, 1, -1), 0, "up from the first row reaches DND")
  assert.equal(inbox.moveStop(stops, 0, -1), 0, "held at the top")
  assert.equal(inbox.moveStop(stops, 3, 1), 4, "down from the last row reaches Clear")
  assert.equal(inbox.moveStop(stops, 4, 1), 4, "held at the bottom")
  assert.equal(inbox.moveStop(stops, 2, 0), 2)
  assert.equal(inbox.moveStop(stops, "x", 1), 1)
  assert.equal(inbox.moveStop([], 0, 1), -1)
  assert.equal(inbox.moveStop(null, 0, 1), -1)
})

// Panel.qml's single call from onCursorStopChanged: the keyboard-vs-pointer
// removal decision, extracted into a pure function (fix round 1).
test("followRemoval: a keyboard delete lands on the neighbour, shown", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )

  // The middle row: the row that slides into its place is the neighbour.
  const afterMiddle = [{ key: "a" }, { key: "c" }, { key: "d" }]
  assert.deepEqual(inbox.followRemoval(afterMiddle, "b", "b", 1, true), {
    key: "c",
    shown: true,
    pendingKey: ""
  })

  // The last row: clamped to the previous one.
  const afterLast = [{ key: "a" }, { key: "b" }]
  assert.deepEqual(inbox.followRemoval(afterLast, "c", "c", 2, true), {
    key: "b",
    shown: true,
    pendingKey: ""
  })

  // The only row: nothing left to show the cursor on.
  assert.deepEqual(inbox.followRemoval([], "a", "a", 0, true), {
    key: "",
    shown: false,
    pendingKey: ""
  })
})

test("followRemoval: a pointer or background removal hides the cursor", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )
  const after = [{ key: "a" }]

  // Nothing armed (a pointer dismiss, or a background prune/expiry).
  assert.deepEqual(inbox.followRemoval(after, "", "b", 1, true), {
    key: "",
    shown: false,
    pendingKey: ""
  })

  // Armed, but for a different key than the one that vanished: still
  // hides. (The arm is left as given here -- harmless, since the cursor
  // can only ever retarget that key through a placeCursor-style write that
  // finds it among a CURRENT stop, which the next followRemoval call would
  // then see as survived and clear; see the "intervening" test below.)
  assert.deepEqual(inbox.followRemoval(after, "z", "b", 1, true), {
    key: "",
    shown: false,
    pendingKey: "z"
  })
})

test("followRemoval: a surviving key is kept exactly as shown, clearing a stale arm", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )
  const stops = [{ key: "a" }, { key: "b" }]

  // A hover-placed cursor (shown false) on a row that still exists stays
  // hidden; a keyboard-shown one (shown true) stays shown. Either way, a
  // stale armed key (here "z", from an unrelated earlier delete) is
  // dropped once the cursor's own key survives.
  assert.deepEqual(inbox.followRemoval(stops, "z", "b", 5, false), {
    key: "b",
    shown: false,
    pendingKey: ""
  })
  assert.deepEqual(inbox.followRemoval(stops, "z", "b", 5, true), {
    key: "b",
    shown: true,
    pendingKey: ""
  })
})

test("followRemoval: an intervening survive clears the arm, so a later vanish only hides (adversarial interleaving)", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )

  // deleteCursor arms "b" for cursorKey "b" (cursor sat at stop 1)...
  const armed = "b"
  const cursorKey = "b"
  const lastStop = 1

  // ...but before that removal lands, a new notification arrives and
  // re-sorts the stops: "b" is still there (survived), just moved. The
  // intervening call must clear the stale arm rather than leave it primed.
  const arrived = [{ key: "x" }, { key: "b" }, { key: "c" }]
  const afterArrival = inbox.followRemoval(arrived, armed, cursorKey, lastStop, true)
  assert.deepEqual(afterArrival, { key: "b", shown: true, pendingKey: "" })

  // Now "b" actually leaves. Because the arm was already cleared, this is
  // an ordinary vanish (hide), never afterRemoval's neighbour -- the stale
  // arm from the delete that preceded the arrival can't fire late.
  const afterRemoval = [{ key: "x" }, { key: "c" }]
  assert.deepEqual(
    inbox.followRemoval(afterRemoval, afterArrival.pendingKey, afterArrival.key, lastStop, true),
    { key: "", shown: false, pendingKey: "" }
  )
})

test("InboxLogic.js's generated copy of CursorLogic answers like the source", () => {
  // Panel.qml imports InboxLogic.js only; this generated copy (fix round 1,
  // tools/js-facade-generator.mjs) exists only because InboxLogic.js's own
  // followRemoval calls afterRemoval internally, with no cross-.js-file
  // import usable from both QML and Node (the same reason
  // araneadev.network/NetworkLogic.js carries its own copy). The rest of
  // CursorLogic rides along unused by InboxLogic's own code; loadPragma
  // runs the copy for real so InboxLogic.js's own function-coverage floor
  // stays honest.
  const assert = require("node:assert/strict")
  const source = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.shared/CursorLogic.js")
  )
  const plain = (value) => JSON.parse(JSON.stringify(value))
  const copy = loadPragma("plugins/araneadev.notifications/InboxLogic.js")
  const rows = [{ key: "a" }, { key: "b" }, { key: "c" }]
  assert.deepEqual(
    plain(copy.reselectIndex(rows, "c", 0)),
    plain(source.reselectIndex(rows, "c", 0))
  )
  assert.deepEqual(plain(copy.followCursor(rows, "b", 0)), plain(source.followCursor(rows, "b", 0)))
  assert.equal(copy.cursorConfirmed(rows, "b", 1), source.cursorConfirmed(rows, "b", 1))
  assert.equal(copy.pressIntent(true, false), source.pressIntent(true, false))
  assert.deepEqual(plain(copy.keepRows({}, "x", rows)), plain(source.keepRows({}, "x", rows)))
  assert.equal(copy.rowKeyMatches(rows, 1, "b"), source.rowKeyMatches(rows, 1, "b"))
  assert.deepEqual(plain(copy.afterRemoval(rows, "b", 1)), plain(source.afterRemoval(rows, "b", 1)))
})

test("DND switch: pending, echo and queued clicks", () => {
  const assert = require("node:assert/strict")
  const inbox = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/InboxLogic.js")
  )
  const idle = inbox.dndIdle()
  assert.deepEqual(idle, { target: null, queued: null })
  assert.deepEqual(inbox.dndView(idle, false), { on: false, busy: false })
  assert.deepEqual(inbox.dndView(null, true), { on: true, busy: false })

  // A click shows the new state at once and pulses until the echo.
  let r = inbox.dndClick(idle, false)
  assert.equal(r.send, true)
  assert.deepEqual(inbox.dndView(r.state, false), { on: true, busy: true })
  assert.deepEqual(inbox.dndClick(null, true).send, false, "null counts as idle")

  // The echo settles it.
  let e = inbox.dndEcho(r.state, true)
  assert.equal(e.send, null)
  assert.deepEqual(e.state, idle)
  assert.deepEqual(inbox.dndView(e.state, true), { on: true, busy: false })

  // A value other than the target keeps waiting; idle ignores echoes.
  assert.deepEqual(inbox.dndEcho(r.state, false), { state: r.state, send: null })
  assert.deepEqual(inbox.dndEcho(idle, true), { state: idle, send: null })
  assert.deepEqual(inbox.dndEcho(null, true).state, idle)

  // Clicks while busy are queued; the last one wins.
  let s = inbox.dndClick(idle, false).state // target on
  let q = inbox.dndClick(s, false) // queue off
  assert.equal(q.send, null, "nothing sent while busy")
  assert.deepEqual(q.state, { target: true, queued: false })
  assert.deepEqual(
    inbox.dndView(q.state, false),
    { on: false, busy: true },
    "shows the queued state"
  )
  e = inbox.dndEcho(q.state, true)
  assert.equal(e.send, false, "the queued state is sent after the echo")
  assert.deepEqual(e.state, { target: false, queued: null })
  assert.deepEqual(inbox.dndEcho(e.state, false).state, idle)

  // An even number of clicks while busy cancels the queue.
  q = inbox.dndClick(inbox.dndClick(s, false).state, false)
  assert.deepEqual(q.state, { target: true, queued: null })
  assert.deepEqual(inbox.dndView(q.state, false), { on: true, busy: true })
  e = inbox.dndEcho(q.state, true)
  assert.equal(e.send, null)
  assert.deepEqual(e.state, idle)

  // A rapid burst: on, off, on, off ends off and sends at most twice.
  let state = idle
  let actual = false
  const sent = []
  for (let i = 0; i < 4; i++) {
    const c = inbox.dndClick(state, actual)
    state = c.state
    if (c.send !== null) sent.push(c.send)
  }
  for (let guard = 0; guard < 5 && state.target !== null; guard++) {
    actual = state.target // the service applies the in-flight value
    const echo = inbox.dndEcho(state, actual)
    state = echo.state
    if (echo.send !== null) sent.push(echo.send)
  }
  assert.deepEqual(sent, [true, false])
  assert.equal(actual, false, "final state matches the last click")
  assert.deepEqual(inbox.dndView(state, actual), { on: false, busy: false })

  // A queued state equal to the echo sends nothing (undefined fields count as unset).
  assert.deepEqual(inbox.dndEcho({ target: true, queued: true }, true), { state: idle, send: null })
  assert.deepEqual(inbox.dndClick({ target: undefined, queued: undefined }, true).send, false)
  assert.deepEqual(inbox.dndView({ target: true, queued: undefined }, false), {
    on: true,
    busy: true
  })
  assert.deepEqual(inbox.dndEcho({ target: true, queued: undefined }, true).state, idle)
})
