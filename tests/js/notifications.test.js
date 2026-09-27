// Logic contract for the notifications modules (moved from tests/notifications.test.sh).
// Run with `node --test tests/js/` (tools/check runs it with coverage).
const path = require("node:path")
const { test } = require("node:test")

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
  assert(inbox.bellGlyph(false) === "󰂚" && inbox.bellGlyph(true) === "󰂛", "bell glyphs")
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

  const logic = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
  assert(typeof logic.historyRows === "undefined", "history replay helper must be gone")

  // --- service bridge: the Aranea bar hands widgets a service-less facade, so
  // the panel finds its own plugin's service through a shared library module.
  const bridgeSrc = require("fs").readFileSync(
    `${root}/plugins/araneadev.notifications/ServiceBridge.js`,
    "utf8"
  )
  assert(bridgeSrc.startsWith(".pragma library"), "bridge must be a shared library module")
  const bridge = {}
  new Function(
    "exports",
    bridgeSrc.replace(".pragma library", "") +
      "\nexports.publish = publish; exports.current = current; exports.retract = retract"
  )(bridge)
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
  const n = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/NotificationLogic.js")
  )
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
  const n = require(`${root}/NotificationLogic.js`)
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
  const n = require(`${root}/NotificationLogic.js`)
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
  const n = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/NotificationLogic.js")
  )
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
  const n = require(
    path.join(__dirname, "..", "..", "plugins/araneadev.notifications/NotificationLogic.js")
  )
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
