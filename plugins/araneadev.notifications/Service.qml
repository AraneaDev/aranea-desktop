// Notification service for the omarchy shell.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import qs.Commons

import "components"
import "NotificationLogic.js" as NotificationLogic
import "InboxLogic.js" as InboxLogic
import "ServiceBridge.js" as ServiceBridge

Item {
  id: service

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  readonly property string home: Quickshell.env("HOME")
  // History + DND live under XDG_STATE_HOME: they're persistent user state
  // (the notifications received, the last-set DND preference), not
  // regeneratable cache that a `rm -rf ~/.cache` should wipe.
  readonly property string stateDir: home + "/.local/state/omarchy/"
  readonly property string settingsPath: stateDir + "notifications.json"
  // Inbox files, image copies and (legacy) popup files live here. See Inbox.qml.
  readonly property string popupStateDir: stateDir + "notifications/"

  property alias inbox: inbox
  Inbox {
    id: inbox
    stateDir: service.popupStateDir
    normalUrgency: NotificationUrgency.Normal
  }

  // Corner radius is shared with the menu and shell panels.
  // It mirrors Hyprland's current decoration:rounding value.
  readonly property int cornerRadius: Style.cornerRadius
  // Toasts are fixed to the top-right corner. They only clear the omarchy bar
  // when the bar occupies the top or right edge, so left/bottom bars do not
  // pull notification popups away from the expected top-right location.
  // Falls back to the bar's default size (26 horizontal / 28 vertical) when
  // shell.bar isn't reachable so the popup never lands on top of the bar.
  readonly property string barPosition: shell && shell.barConfig ? String(shell.barConfig.position || "top") : "top"
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden ? Math.max(0, shell.bar.barSize) : defaultBarSize
  readonly property int barClearance: liveBarSize + Style.gapsOut

  // Live Notification objects by originalId, kept OUT of the ListModels: a
  // QObject stored in a model role becomes a dangling C++ pointer when the
  // server destroys the notification (sender close, DND untrack, dismiss),
  // and the next read of that role segfaults in QQmlListModel::data. A JS
  // map only holds a wrapper, which degrades to a catchable error instead.
  property var liveRefs: ({})

  // Live Notification objects of inbox entries, by inbox file name. A stored
  // notification stays tracked while it waits in the center, so a sender's
  // replaces_id update lands on the same entry and a click can still run the
  // sender's own action. Empty after a shell restart: those entries fall back
  // to execArgv / focusing the app.
  property var inboxRefs: ({})

  // Popups restored from a previous shell process, keyed by their file
  // name (timestamp-originalId) since ids alone repeat across server
  // generations. The replaces_id handling and liveRefs lookups must not
  // match these rows against fresh notifications.
  property var restoredPopups: ({})

  // PersistentProperties handles in-process QML reloads. The on-disk
  // notifications.json file is the cross-restart backstop — its `dnd` key
  // is hydrated into persisted.doNotDisturb on startup and written back via
  // a debounced save timer.
  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-notifications"
    property bool doNotDisturb: false
    onDoNotDisturbChanged: {
      // Suppress the write that load-time hydration would otherwise trigger.
      if (service._hydrating) return
      service.scheduleSettingsSave()
    }
  }

  // Guards onDoNotDisturbChanged while we're hydrating from disk so the
  // hydration assignment doesn't immediately schedule a write-back.
  property bool _hydrating: false

  readonly property alias doNotDisturb: persisted.doNotDisturb
  // Optional quiet-hours window, for example `22:00-07:00`. Suppressed
  // notifications still enter history through the same path as DND, while
  // critical CLI alerts retain the existing explicit bypass rule.
  readonly property string quietHoursWindow: Quickshell.env("ARANEA_QUIET_HOURS")
  property int quietHoursTick: 0
  readonly property bool quietHours: quietHoursTick >= 0 && NotificationLogic.isWithinQuietHours(quietHoursWindow, new Date())

  Timer {
    interval: 60000
    repeat: true
    running: service.quietHoursWindow.length > 0
    onTriggered: service.quietHoursTick++
  }

  function setDoNotDisturb(value: bool): void {
    persisted.doNotDisturb = !!value
  }

  // popupModel feeds the on-screen toast stack — the only model the service
  // keeps. Stored notifications also live in the inbox (see Inbox.qml).
  //
  // Aliased as a property so consumers outside this Item's id scope can bind
  // to it. QML ids aren't visible to external consumers without the alias.
  property alias popupModel: popupModel
  ListModel { id: popupModel }

  // Aranea motion preference, shared with the OSD: `off` in the state file
  // (or ARANEA_REDUCED_MOTION=1) removes the swipe slide animation.
  property bool motionEnabled: Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
  readonly property string motionStatePath: (Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")) + "/aranea/motion"

  FileView {
    path: service.motionStatePath
    watchChanges: true
    printErrors: false
    onLoaded: service.motionEnabled = String(text || "").trim() !== "off"
    onLoadFailed: service.motionEnabled = Quickshell.env("ARANEA_REDUCED_MOTION") !== "1"
    onFileChanged: reload()
  }

  readonly property int lowPopupDuration: 5000
  readonly property int normalPopupDuration: 8000
  readonly property int maxPopupDuration: 30000
  // Critical toasts (e.g. browser "requireInteraction" web notifications)
  // otherwise never auto-expire; still give them their own screen time,
  // just capped so they can't sit there indefinitely.
  readonly property int criticalPopupDuration: 60000

  function durationFor(urgency: int, expireTimeout: int): int {
    switch (urgency) {
    case NotificationUrgency.Critical:
      return criticalPopupDuration
    case NotificationUrgency.Low:
      return Math.min(maxPopupDuration, Math.max(lowPopupDuration, requestedDuration(expireTimeout)))
    default:
      return Math.min(maxPopupDuration, Math.max(normalPopupDuration, requestedDuration(expireTimeout)))
    }
  }

  function requestedDuration(expireTimeout: int): int {
    // FreeDesktop notification spec (and Quickshell) report expireTimeout in
    // milliseconds, so pass it through directly.
    var ms = Number(expireTimeout || 0)
    if (!isFinite(ms) || ms <= 0) return 0
    return Math.round(ms)
  }

  // DND bypass: only let through notifications we trust to be intentional
  // and rare.
  //   - omarchy-action: a user-action confirmation toast ("Theme changed",
  //     "Screenshot saved"). The user JUST did something — their feedback
  //     should show.
  //   - urgency=critical AND app_name=notify-send: bare-CLI emergency alerts.
  //     Trusted because it's almost always omarchy or system shell scripts —
  //     chat apps set app_name to their brand (Discord/Slack/Vesktop), which
  //     falls outside this rule.
  function shouldBypassDnd(notification): bool {
    return NotificationLogic.shouldBypassDnd(notification, NotificationUrgency.Critical)
  }

  function snapshotOf(notification): var {
    return NotificationLogic.snapshotOf(notification, Date.now())
  }

  function isTransient(notification): bool {
    try {
      return !!(notification.hints && notification.hints["transient"])
    } catch (e) {
      return false
    }
  }

  function shouldStore(notification, snapshot): bool {
    return InboxLogic.shouldStore(
      NotificationLogic.isEphemeralApp(snapshot.app), snapshot.urgency, isTransient(notification))
  }

  function handleNotification(notification) {
    // Without `tracked = true` the Notification object is destroyed as soon
    // as this signal handler returns, which would null out the `ref` we just
    // captured for the popup card.
    notification.tracked = true
    var snapshot = snapshotOf(notification)

    // Everything worth keeping goes to the center, never to a toast.
    if (shouldStore(notification, snapshot)) {
      storeInInbox(notification, snapshot)
      return
    }

    // What is left is Omarchy's own action feedback (and `transient`
    // notifications): a brief toast, never stored. DND drops it unless it
    // is the kind shouldBypassDnd trusts.
    if ((service.doNotDisturb || service.quietHours) && !shouldBypassDnd(notification)) {
      notification.tracked = false
      return
    }

    liveRefs[snapshot.originalId] = notification
    // Guard the delete: a newer notification may have reused this originalId
    // (freedesktop replaces_id) and taken over the map slot.
    notification.closed.connect(function() {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })
    watchForUpdates(notification, snapshot)
    // Qt.callLater avoids "QV4::Object::insertMember" crashes when a
    // Repeater is mid-incubation while we mutate its model.
    Qt.callLater(function() {
      removePopupsByOriginalId(snapshot.originalId, NotificationLogic.popupFileName(snapshot))
      popupModel.insert(0, snapshot)
      // An update that arrived while the insert was deferred found no row to
      // write to, and a property that already changed will not change again.
      // Reading the object once the row exists catches up on it.
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    })
  }

  function storeInInbox(notification, snapshot) {
    var fileName = NotificationLogic.popupFileName(snapshot)
    inboxRefs[fileName] = notification
    // The sender closing its notification (it was read elsewhere, the app
    // quit) only ends the live link; the entry waits until the user clears it.
    notification.closed.connect(function() {
      if (service.inboxRefs[fileName] === notification) delete service.inboxRefs[fileName]
    })
    inbox.upsert(snapshot)
    var refresh = function() { service.refreshInbox(notification, fileName, snapshot.originalId, snapshot.timestamp) }
    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }
  }

  // A replaces_id update rewrites the tracked object; copy it into the same
  // inbox entry (same file name), as long as the user has not cleared it.
  function refreshInbox(notification, fileName, originalId, timestamp) {
    if (service.inboxRefs[fileName] !== notification || !inbox.has(fileName)) return
    var updated
    try {
      updated = NotificationLogic.replacementSnapshot(notification, originalId, timestamp)
    } catch (e) {
      return
    }
    var current = inbox.get(fileName)
    if (current && !NotificationLogic.popupRowChanged(current, updated)) return
    inbox.upsert(updated)
  }

  // Everything the card draws. A change to any of these is a client updating
  // the notification in place, which is the only kind of update we ever hear
  // about after the popup exists.
  readonly property var updateSignals: [
    "summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged",
    "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged"
  ]

  // A client that updates a notification through replaces_id does not produce
  // a second onNotification: the server writes the new content onto the object
  // we are already holding. The card draws a snapshot copied out of that
  // object — deliberately, since the object itself must stay out of the model
  // — so nothing reaches the screen until we copy it again.
  function watchForUpdates(notification, snapshot) {
    function refresh() {
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    }

    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function") signal.connect(refresh)
    }
  }

  function refreshPopup(notification, originalId, timestamp) {
    // A newer notification may have taken this id over, and the object may
    // outlive its popup — in both cases there is nothing here to refresh.
    if (service.liveRefs[originalId] !== notification) return

    var updated
    try {
      updated = NotificationLogic.replacementSnapshot(notification, originalId, timestamp)
    } catch (e) {
      // Object torn down by the server while the signal was in flight.
      return
    }

    var roles = NotificationLogic.popupRoles()
    for (var i = 0; i < popupModel.count; i++) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp) continue
      if (!NotificationLogic.popupRowChanged(row, updated)) return
      for (var r = 0; r < roles.length; r++) popupModel.setProperty(i, roles[r], updated[roles[r]])
      return
    }
  }

  // A restored row carries an id from the previous server generation, and
  // the new server hands out ids from 1 again — so a fresh notification
  // with the same originalId is a coincidence, not the same notification.
  // The timestamp (via the file name) disambiguates: it travels with the
  // row through every model and file round-trip.
  function isRestoredRow(row) {
    return !!row && !!restoredPopups[NotificationLogic.popupFileName(row)]
  }

  // A notification arriving under an originalId a popup on screen already
  // holds supersedes it, so that row leaves the screen. Its file is deleted
  // rather than archived: the row taking its place archives itself when it
  // goes, and history would otherwise hold two entries for what the sender
  // means as one notification.
  // keepFileName is the replacement's own file: a same-millisecond
  // replacement shares the replaced row's filename, and the new write is
  // already queued — deleting that path here would erase the replacement's
  // only file.
  function removePopupsByOriginalId(originalId, keepFileName) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId) continue
      // Not a replaces_id match — see isRestoredRow. Removing it here
      // would silently kill a restored critical alert on an unrelated ping.
      if (isRestoredRow(row)) continue
      popupModel.remove(i)
    }
  }

  function dismissPopup(index: int): void {
    removePopup(index, "dismiss")
  }

  function expirePopup(index: int): void {
    removePopup(index, "expire")
  }

  function removePopup(index: int, reason: string): void {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)
    var originalId = entry ? entry.originalId : -1
    // A restored row has no live server object, and its old-generation id
    // may meanwhile belong to a fresh notification — resolving liveRefs by
    // id would dismiss that unrelated notification at the server.
    var restored = isRestoredRow(entry)
    var ref = !restored && originalId >= 0 ? liveRefs[originalId] : null
    if (entry && restored) delete restoredPopups[NotificationLogic.popupFileName(entry)]
    popupModel.remove(index)
    if (ref) {
      try {
        if (ref.tracked) {
          if (reason === "expire" && typeof ref.expire === "function") ref.expire()
          else ref.dismiss()
        }
      } catch (e) {
        // Object already torn down by the server — nothing to dismiss.
      }
    }
  }

  function clearPopups(): void {
    while (popupModel.count > 0) dismissPopup(0)
  }

  function toggleCenter(): void {
    if (service.shell && typeof service.shell.toggle === "function")
      service.shell.toggle("araneadev.notifications")
  }

  function openCenter(): void {
    if (service.shell && typeof service.shell.summon === "function")
      service.shell.summon("araneadev.notifications", "")
  }

  // Tell a still-live sender its notification is gone, then forget it.
  function releaseInboxRef(fileName: string): void {
    var ref = inboxRefs[fileName]
    delete inboxRefs[fileName]
    if (!ref) return
    try {
      if (ref.tracked) ref.dismiss()
    } catch (e) {
      // Already torn down by the server.
    }
  }

  function clearInbox(): void {
    for (var i = 0; i < inbox.model.count; i++) releaseInboxRef(inbox.model.get(i).fileName)
    inbox.clear()
  }

  function dismissInbox(fileName: string): void {
    releaseInboxRef(fileName)
    inbox.remove(fileName)
  }

  function dismissGroup(app: string): void {
    var names = []
    for (var i = 0; i < inbox.model.count; i++) {
      var row = inbox.model.get(i)
      if (String(row.app || "unknown") === app) names.push(row.fileName)
    }
    for (var j = 0; j < names.length; j++) dismissInbox(names[j])
  }

  // Omarchy's argv first, then the sender's own default action while it is
  // still live, then focusing the sending app.
  function invokeInbox(fileName: string): void {
    var entry = inbox.get(fileName)
    if (!entry) return
    var argv = NotificationLogic.parseExecArgv(entry.execArgv)
    if (argv) Util.execArgv(argv)
    else if (!invokeDefaultAction(inboxRefs[fileName])) focusApp(entry)
    dismissInbox(fileName)
  }

  function newestInboxFile(): string {
    return inbox.model.count > 0 ? inbox.model.get(0).fileName : ""
  }

  function invokeDefaultAction(ref): bool {
    try {
      if (ref && ref.actions) {
        for (var i = 0; i < ref.actions.length; i++) {
          var action = ref.actions[i]
          if (action && action.identifier === "default") {
            action.invoke()
            return true
          }
        }
      }
    } catch (e) {
      // Notification already torn down by the server.
      console.warn("invoke default failed:", e)
    }
    return false
  }

  // Run the popup's click action, then dismiss. Omarchy's own toasts carry the
  // action as an argv vector in the `execArgv` role (see execArgvFromHints),
  // which the persistence files preserve, so restored toasts stay clickable.
  // Third-party clients register a libnotify action under the canonical
  // identifier "default" instead; that one only works while the sender is live.
  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count) return
    var entry = popupModel.get(index)

    // Run the argv (via Util.execArgv, no shell interpretation). Detached so it
    // outlives the shell, which installer toasts depend on: they restart it.
    var argv = NotificationLogic.parseExecArgv(entry ? entry.execArgv : "")
    if (argv) {
      Util.execArgv(argv)
      removePopup(index, "invoke")
      return
    }
    // Restored rows have no live actions, and looking up liveRefs by their
    // old-generation id could fire an unrelated fresh notification's action.
    var ref = entry && !isRestoredRow(entry) ? liveRefs[entry.originalId] : null
    var invoked = invokeDefaultAction(ref)
    // Chat apps (Slack, Discord, Vesktop, etc.) rarely register a "default"
    // libnotify action — they just expect clicking the notification to
    // focus their window. Fall back to focusing the sending app by class so
    // that click-to-jump actually works.
    if (!invoked) focusApp(entry)
    removePopup(index, "invoke")
  }

  // Try to focus an existing Hyprland window matching the notification's
  // sender. The helper handles case-insensitive class matching.
  function focusApp(entry) {
    if (!entry || !entry.app) return
    focusAppProc.command = [
      service.omarchyPath + "/bin/omarchy-hyprland-focus-app",
      String(entry.app)
    ]
    focusAppProc.running = true
  }

  Process { id: focusAppProc; running: false }

  // ---------------------------------------------------- settings persistence

  FileView {
    id: settingsFile
    path: service.settingsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadSettings(text())
    // First-run: the file doesn't exist yet. Without this branch,
    // `settingsLoaded` stays false forever and `scheduleSettingsSave` becomes
    // a no-op — so the file is never created and the DND preference vanishes
    // on shell restart.
    onLoadFailed: service.loadSettings("")
  }

  Timer {
    id: settingsSaveTimer
    interval: 200
    repeat: false
    onTriggered: service.flushSettings()
  }

  function scheduleSettingsSave(): void {
    if (!service.settingsLoaded) return
    settingsSaveTimer.restart()
  }

  property bool settingsLoaded: false

  function loadSettings(raw: string): void {
    // FileView can fire onLoaded more than once during startup — the implicit
    // preload when `path` resolves, plus the explicit `settingsFile.reload()`
    // in Component.onCompleted can both end up calling here.
    if (service.settingsLoaded) return

    var parsed = NotificationLogic.parseSettings(raw)
    if (parsed.error) console.warn("notifications: settings parse failed:", parsed.errorMessage || "")

    if (parsed.dnd !== null) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }

    service.settingsLoaded = true
    // Versions before the history moved into its own directory kept every
    // notification in here. Rewrite once so that dead payload doesn't sit in
    // the file until the next DND toggle happens to clear it.
    if (parsed.legacy) service.scheduleSettingsSave()
  }

  function flushSettings(): void {
    settingsFile.setText(JSON.stringify({ version: 3, dnd: persisted.doNotDisturb }, null, 2) + "\n")
  }

  Component.onDestruction: ServiceBridge.retract(service)

  Component.onCompleted: {
    // The bar widget (Panel.qml) finds this service here; see ServiceBridge.js.
    ServiceBridge.publish(service)
    Qt.callLater(function() {
      settingsFile.reload()
      // Load the inbox, migrating pre-inbox popup files into it.
      inbox.load(null)
    })
  }

  // ---------------------------------------------------- IPC

  IpcHandler {
    target: "notifications"

    function dndState(): string {
      return service.doNotDisturb ? "on" : "off"
    }

    function toggleDnd(): string {
      service.setDoNotDisturb(!service.doNotDisturb)
      return dndState()
    }

    function setDnd(value: string): string {
      var v = String(value || "").toLowerCase()
      var on = v === "true" || v === "1" || v === "on" || v === "yes"
      service.setDoNotDisturb(on)
      return dndState()
    }

    function isDnd(): string {
      return dndState()
    }

    function quietState(): string {
      if (!service.quietHoursWindow) return "off"
      return service.quietHours ? "on" : "scheduled"
    }

    function quietWindow(): string {
      return service.quietHoursWindow || "off"
    }

    // Kept for Omarchy's SUPER+SHIFT+ALT+comma binding; opens the center.
    function showHistory(): string {
      service.toggleCenter()
      return "ok"
    }

    // `clear` empties the inbox (and dismisses the toasts that belong to it).
    function clear(): string {
      service.clearInbox()
      return "ok"
    }

    function center(): string {
      service.toggleCenter()
      return "ok"
    }

    function count(): string {
      return String(service.inbox.count)
    }

    // Omarchy's SUPER+SHIFT+comma: clear feedback toasts and open the center.
    // Never bulk-deletes the inbox from a single keypress.
    function dismissAll(): string {
      service.clearPopups()
      service.openCenter()
      return "ok"
    }

    // Dismiss the feedback toast on screen, else the newest inbox entry.
    function dismissOne(): string {
      if (popupModel.count > 0) {
        service.dismissPopup(0)
        return "ok"
      }
      var fileName = service.newestInboxFile()
      if (!fileName) return "none"
      service.dismissInbox(fileName)
      return "ok"
    }

    // Open the newest inbox entry (its action or its app).
    function invokeLast(): string {
      var fileName = service.newestInboxFile()
      if (!fileName) return "none"
      service.invokeInbox(fileName)
      return "ok"
    }

    // Take a toast off the screen by summary substring, used by the
    // first-run notifications once their action has been clicked.
    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle) return "none"
      var hit = false
      for (var i = popupModel.count - 1; i >= 0; i--) {
        var row = popupModel.get(i)
        if (row && String(row.summary || "").indexOf(needle) !== -1) {
          service.dismissPopup(i)
          hit = true
        }
      }
      return hit ? "ok" : "none"
    }

    function ping(): string { return "ok" }
  }

  // ---------------------------------------------------- server

  NotificationServer {
    id: server
    keepOnReload: false
    imageSupported: true
    actionsSupported: true
    bodyMarkupSupported: true
    bodyHyperlinksSupported: true
    persistenceSupported: true

    onNotification: function(notification) {
      service.handleNotification(notification)
    }
  }

  // -------------------------------------------------------------- popup UI
  //
  // One PanelWindow per output (Variants on Quickshell.screens) holding the
  // stacked toast cards. Layer is Overlay, exclusionMode Ignore, no
  // keyboard focus — popups are passive surfaces and must never steal input
  // from the focused application.

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData
      screen: modelData
      visible: popupModel.count > 0

      WlrLayershell.namespace: "omarchy-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      readonly property var popupPlacement: NotificationLogic.popupPlacement(
        service.barPosition, service.barClearance, Style.gapsOut)

      // Full-screen, fixed-size surface (like the OSD overlay). Adding or
      // removing a toast changes only the content inside; the Wayland surface
      // never resizes, so the compositor can't briefly scale a stale buffer --
      // which is what stretched/squished the cards during count changes.
      anchors { top: true; bottom: true; left: true; right: true }

      // Keep the surface click-through except over the toast column, so the
      // rest of the (invisible) full-screen overlay never eats input.
      mask: Region { item: popupColumn }

      ColumnLayout {
        id: popupColumn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top
        anchors.rightMargin: popupWindow.popupPlacement.margins.right
        spacing: Style.space(8)

        Repeater {
          model: popupModel

          // The delegate is a slot Item that owns lifetime timer state. The
          // actual visuals live in NotificationCard, which the history panel
          // also reuses.
          delegate: Item {
            id: cardSlot
            required property int index
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string glyph
            required property int urgency
            required property double expireTimeout
            required property double timestamp

            // Each card sizes itself based on mode (text vs media); the slot
            // tracks the card so the column auto-fits to whichever is widest.
            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: service.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            property real remainingLifetime: 1.0
            readonly property bool ticking: cardSlot.lifetime > 0 && !card.hovered && !card.dragging

            // A client updating this notification in place rewrites the row
            // under the card (see refreshPopup). New text deserves a full look,
            // so the countdown starts over instead of running out the clock the
            // superseded text was already most of the way through. Delegates
            // keep their own row as the model changes around them, so only a
            // real content change lands here.
            onSummaryChanged: cardSlot.remainingLifetime = 1.0
            onBodyChanged: cardSlot.remainingLifetime = 1.0
            onImageChanged: cardSlot.remainingLifetime = 1.0

            Timer {
              interval: 50
              repeat: true
              running: cardSlot.ticking
              onTriggered: {
                if (cardSlot.lifetime <= 0) return
                cardSlot.remainingLifetime -= 50.0 / cardSlot.lifetime
                if (cardSlot.remainingLifetime <= 0) {
                  cardSlot.remainingLifetime = 0
                  service.expirePopup(cardSlot.index)
                }
              }
            }

            NotificationCard {
              id: card
              anchors.right: parent.right
              app: cardSlot.app
              appIcon: cardSlot.appIcon
              summary: cardSlot.summary
              body: cardSlot.body
              image: cardSlot.image
              urgency: cardSlot.urgency
              timestamp: cardSlot.timestamp
              cornerRadius: service.cornerRadius
              fontFamily: service.shell && service.shell.bar ? service.shell.bar.fontFamily : ""
              glyph: cardSlot.glyph

              motionEnabled: service.motionEnabled

              onCloseRequested: service.dismissPopup(cardSlot.index)
              onSwipeDismissed: service.dismissPopup(cardSlot.index)
              onCardClicked: service.invokePopupDefault(cardSlot.index)
            }
          }
        }
      }
    }
  }
}
