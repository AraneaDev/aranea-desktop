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

  // --- lifecycle outcome
  assert(inbox.removesFromInbox("expire") === false, "expired toast must stay in the inbox")
  assert(inbox.removesFromInbox("dismiss") === true, "dismissed toast must leave the inbox")
  assert(inbox.removesFromInbox("invoke") === true, "invoked toast must leave the inbox")

  // --- replaces_id keeps one entry (Review Focus 2)
  let rows = [{ fileName: "b" }, { fileName: "a" }]
  rows = inbox.upsertOrder(rows, { fileName: "a", summary: "v2" })
  assert(rows.length === 2 && rows[1].summary === "v2", "same fileName must update in place")
  rows = inbox.upsertOrder(rows, { fileName: "c" })
  assert(rows.length === 3 && rows[0].fileName === "c", "new fileName must be prepended")

  // --- pruning
  const now = 1000 * DAY
  const e = (name, ageDays, urgency, onScreen) => ({
    fileName: name,
    timestamp: now - ageDays * DAY,
    urgency: urgency,
    onScreen: !!onScreen
  })
  let pruned = inbox.pruneInbox(
    [e("old", 8, 1), e("oldCrit", 8, 2), e("fresh", 1, 1), e("oldLive", 9, 1, true)],
    now
  )
  assert(
    pruned.drop.map((x) => x.fileName).join() === "old",
    "only non-critical, off-screen entries age out"
  )
  assert(
    pruned.keep.map((x) => x.fileName).join() === "fresh,oldCrit,oldLive",
    "keep must be newest-first"
  )

  const many = []
  for (let i = 0; i < 103; i++)
    many.push({
      fileName: "n" + i,
      timestamp: now - i * 1000,
      urgency: i === 102 ? 2 : 1,
      onScreen: false
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
    crits.push({ fileName: "c" + i, timestamp: now - i * 1000, urgency: 2, onScreen: false })
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

  // --- onScreen round-trip through the persisted format (Review Focus 1, 3)
  const logic = require(`${root}/plugins/araneadev.notifications/NotificationLogic.js`)
  const live = logic.popupEntry(
    { id: 3, originalId: 3, app: "Slack", timestamp: 5, onScreen: true, deadline: 99 },
    1
  )
  assert(
    live.onScreen === true && live.deadline === 99,
    "onScreen and deadline must survive popupEntry"
  )
  const parsed = logic.parsePopupFiles(
    logic.serializePopup({ id: 4, originalId: 4, timestamp: 6, onScreen: false }, 1),
    1
  )
  assert(
    parsed.length === 1 && parsed[0].onScreen === false,
    "onScreen=false must survive serialize/parse"
  )
  const legacy = logic.popupEntry({ id: 5, originalId: 5, timestamp: 7 }, 1)
  assert(
    legacy.onScreen === undefined,
    "legacy entries carry no onScreen; Inbox.qml treats them as on screen"
  )
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
