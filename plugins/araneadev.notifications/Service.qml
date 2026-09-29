// Notification service for the omarchy shell: the freedesktop notification
// server (NotificationDaemon.qml), the feedback toast stack (Toasts.qml), the
// inbox (Inbox.qml), DND and quiet hours, and the `notifications` IPC target.
// omarchy-shell loads it as this plugin's service entry point (manifest.json);
// Panel.qml renders its state.

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications
import qs.Commons
import "../araneadev.shared" as Aranea

import "NotificationLogic.js" as NotificationLogic
import "InboxLogic.js" as InboxLogic
import "ServiceBridge.js" as ServiceBridge

Item {
  id: service

  // Injected by omarchy-shell (the first-party service loader).
  property var shell: null

  // Whether to create the toast windows (Toasts.qml); tests switch it off.
  property bool windowEnabled: true
  // Whether to register the notification server (NotificationDaemon.qml);
  // tests switch it off so they never take over the desktop's notifications.
  property bool serverEnabled: true
  // The toast windows, once created; null offscreen.
  property var toasts: null
  // The notification server, once created; null in tests.
  property var server: null

  // Omarchy install root ($OMARCHY_PATH), for omarchy-hyprland-focus-app.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // The user's home directory ($HOME).
  readonly property string home: Quickshell.env("HOME")
  // History + DND live under XDG_STATE_HOME: they're persistent user state
  // (the notifications received, the last-set DND preference), not
  // regeneratable cache that a `rm -rf ~/.cache` should wipe.
  property string stateDir: home + "/.local/state/omarchy/"
  // JSON file holding the last-set DND preference.
  readonly property string settingsPath: stateDir + "notifications.json"
  // Inbox files, image copies and (legacy) popup files live here. See Inbox.qml.
  readonly property string popupStateDir: stateDir + "notifications/"

  // The stored notifications; Panel.qml reads its model, count and revision.
  property alias inbox: inbox
  Inbox {
    id: inbox
    stateDir: service.popupStateDir
    normalUrgency: NotificationUrgency.Normal
    // Pruned entries release their sender, like a manual dismiss.
    onPruned: function (fileName) {
      service.releaseInboxRef(fileName)
    }
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
  // True when the bar sits on the left or right edge.
  readonly property bool barVertical: barPosition === "left" || barPosition === "right"
  // Style's default bar thickness for the bar's orientation.
  readonly property int defaultBarSize: barVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal
  // The live bar's size, or defaultBarSize when shell.bar is missing or hidden.
  readonly property int liveBarSize: shell && shell.bar && !shell.bar.barHidden ? Math.max(0, shell.bar.barSize) : defaultBarSize
  // Distance toasts keep from the bar's edge: bar size plus the outer gap.
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
  // The last snapshot each live sender gave for its inbox entry (by file
  // name), so refreshInbox can tell a real update from a repeat signal.
  property var liveSnapshots: ({})

  // Pause holds per toast (key: timestamp-originalId); a hover or drag on any
  // screen's copy holds it, so no screen can expire a toast being read.
  property var popupHolds: ({})

  // Adds or releases one pause hold on the toast with this key.
  function holdPopup(key: string, on: bool): void {
    service.popupHolds = NotificationLogic.holdPopup(service.popupHolds, key, on)
  }

  // Whether any screen holds the toast with this key.
  function popupHeld(key: string): bool {
    return (service.popupHolds[key] || 0) > 0
  }

  // PersistentProperties handles in-process QML reloads. The on-disk
  // notifications.json file is the cross-restart backstop — its `dnd` key
  // is hydrated into persisted.doNotDisturb on startup and written back via
  // a debounced save timer.
  PersistentProperties {
    id: persisted
    reloadableId: "omarchy-notifications"
    property bool doNotDisturb: false
    onReloaded: service.reloadedSettings = true
    onDoNotDisturbChanged: {
      // Suppress the write that load-time hydration would otherwise trigger.
      if (service._hydrating)
        return
      service.scheduleSettingsSave()
    }
  }

  // Set when PersistentProperties carried values over a reload; the file must not overwrite them.
  property bool reloadedSettings: false

  // Guards onDoNotDisturbChanged while we're hydrating from disk so the
  // hydration assignment doesn't immediately schedule a write-back.
  property bool _hydrating: false

  // Do Not Disturb: drops feedback toasts unless shouldBypassDnd lets them through.
  readonly property alias doNotDisturb: persisted.doNotDisturb
  // Optional quiet-hours window, for example `22:00-07:00`. Suppressed
  // notifications still enter history through the same path as DND, while
  // critical CLI alerts retain the existing explicit bypass rule.
  readonly property string quietHoursWindow: Quickshell.env("ARANEA_QUIET_HOURS")
  // True while the current time is inside quietHoursWindow; acts like DND.
  readonly property bool quietHours: NotificationLogic.isWithinQuietHours(quietHoursWindow, quietClock.date)

  // Minute clock for quiet hours; runs only while a window is set.
  SystemClock {
    id: quietClock
    precision: SystemClock.Minutes
    enabled: service.quietHoursWindow.length > 0
  }

  // Turns DND on or off; the change is persisted to settingsPath.
  function setDoNotDisturb(value: bool): void {
    persisted.doNotDisturb = !!value
  }

  // popupModel feeds the on-screen toast stack — the only model the service
  // keeps. Stored notifications also live in the inbox (see Inbox.qml).
  //
  // Aliased as a property so consumers outside this Item's id scope can bind
  // to it. QML ids aren't visible to external consumers without the alias.
  property alias popupModel: popupModel
  ListModel {
    id: popupModel
  }

  // Aranea motion preference, shared with the OSD: `off` in the state file
  // (or ARANEA_REDUCED_MOTION=1) removes the swipe slide animation.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Shared Aranea motion state file.
  readonly property string motionStatePath: Aranea.RuntimePaths.motionStatePath

  // Minimum on-screen time of a low-urgency toast, in ms.
  readonly property int lowPopupDuration: 5000
  // Minimum on-screen time of a normal-urgency toast, in ms.
  readonly property int normalPopupDuration: 8000
  // Upper bound for a sender-requested toast lifetime, in ms.
  readonly property int maxPopupDuration: 30000
  // Critical toasts (e.g. browser "requireInteraction" web notifications)
  // otherwise never auto-expire; still give them their own screen time,
  // just capped so they can't sit there indefinitely.
  readonly property int criticalPopupDuration: 60000

  // A toast's lifetime in ms: criticalPopupDuration for critical urgency, else the
  // sender's expireTimeout clamped between the urgency's minimum and maxPopupDuration.
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

  // The sender's expireTimeout in whole ms, or 0 when unset or invalid.
  function requestedDuration(expireTimeout: int): int {
    // FreeDesktop notification spec (and Quickshell) report expireTimeout in
    // milliseconds, so pass it through directly.
    var ms = Number(expireTimeout || 0)
    if (!isFinite(ms) || ms <= 0)
      return 0
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

  // Plain model row for a notification, stamped with the current time.
  function snapshotOf(notification): var {
    return NotificationLogic.snapshotOf(notification, Date.now())
  }

  // Whether the sender set the freedesktop `transient` hint (show, never store).
  function isTransient(notification): bool {
    try {
      return !!(notification.hints && notification.hints["transient"])
    } catch (e) {
      return false
    }
  }

  // Whether a notification goes to the inbox (see InboxLogic.shouldStore).
  function shouldStore(notification, snapshot): bool {
    return InboxLogic.shouldStore(NotificationLogic.isEphemeralApp(snapshot.app), snapshot.urgency, isTransient(notification))
  }

  // Entry point for every new notification: stores it in the inbox, drops it
  // under DND/quiet hours, or shows it as a feedback toast.
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
    notification.closed.connect(function () {
      if (service.liveRefs[snapshot.originalId] === notification)
        delete service.liveRefs[snapshot.originalId]
    })
    watchForUpdates(notification, snapshot)
    // Qt.callLater avoids "QV4::Object::insertMember" crashes when a
    // Repeater is mid-incubation while we mutate its model.
    Qt.callLater(function () {
      removePopupsByOriginalId(snapshot.originalId)
      popupModel.insert(0, snapshot)
      // An update that arrived while the insert was deferred found no row to
      // write to, and a property that already changed will not change again.
      // Reading the object once the row exists catches up on it.
      service.refreshPopup(notification, snapshot.originalId, snapshot.timestamp)
    })
  }

  // Adds a notification to the inbox and keeps its live object, so later
  // replaces_id updates rewrite the same entry.
  function storeInInbox(notification, snapshot) {
    var fileName = NotificationLogic.popupFileName(snapshot)
    inboxRefs[fileName] = notification
    liveSnapshots[fileName] = snapshot
    // The sender closing its notification (it was read elsewhere, the app
    // quit) only ends the live link; the entry waits until the user clears it.
    notification.closed.connect(function () {
      if (service.inboxRefs[fileName] === notification) {
        delete service.inboxRefs[fileName]
        delete service.liveSnapshots[fileName]
      }
    })
    inbox.upsert(snapshot)
    var refresh = function () {
      service.refreshInbox(notification, fileName, snapshot.originalId, snapshot.timestamp)
    }
    for (var i = 0; i < updateSignals.length; i++) {
      var signal = notification[updateSignals[i]]
      if (signal && typeof signal.connect === "function")
        signal.connect(refresh)
    }
  }

  // A replaces_id update rewrites the tracked object; copy it into the same
  // inbox entry (same file name), as long as the user has not cleared it.
  function refreshInbox(notification, fileName, originalId, timestamp) {
    if (service.inboxRefs[fileName] !== notification || !inbox.has(fileName))
      return
    var updated
    try {
      updated = NotificationLogic.replacementSnapshot(notification, originalId, timestamp)
    } catch (e) {
      return
    }
    // Compare with what the sender sent last time, not with the model: the
    // model shows persisted copies, which reuse one path per entry, so a
    // change of image alone would look like no change.
    var previous = service.liveSnapshots[fileName]
    if (previous && !NotificationLogic.popupRowChanged(previous, updated))
      return
    service.liveSnapshots[fileName] = updated
    inbox.upsert(updated)
  }

  // Everything the card draws. A change to any of these is a client updating
  // the notification in place, which is the only kind of update we ever hear
  // about after the popup exists.
  readonly property var updateSignals: ["summaryChanged", "bodyChanged", "appNameChanged", "appIconChanged", "imageChanged", "urgencyChanged", "expireTimeoutChanged", "hintsChanged"]

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
      if (signal && typeof signal.connect === "function")
        signal.connect(refresh)
    }
  }

  // Copies an updated notification object into its toast row when anything the
  // card draws changed.
  function refreshPopup(notification, originalId, timestamp) {
    // A newer notification may have taken this id over, and the object may
    // outlive its popup — in both cases there is nothing here to refresh.
    if (service.liveRefs[originalId] !== notification)
      return
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
      if (!row || row.originalId !== originalId || row.timestamp !== timestamp)
        continue
      if (!NotificationLogic.popupRowChanged(row, updated))
        return
      for (var r = 0; r < roles.length; r++)
        popupModel.setProperty(i, roles[r], updated[roles[r]])
      return
    }
  }

  // A notification arriving under an originalId a toast on screen already
  // holds supersedes it, so that toast leaves the screen.
  function removePopupsByOriginalId(originalId) {
    for (var i = popupModel.count - 1; i >= 0; i--) {
      var row = popupModel.get(i)
      if (!row || row.originalId !== originalId)
        continue
      popupModel.remove(i)
    }
  }

  // Removes the toast at index and dismisses its notification at the server.
  function dismissPopup(index: int): void {
    removePopup(index, "dismiss")
  }

  // Removes the toast at index and reports it expired to the server.
  function expirePopup(index: int): void {
    removePopup(index, "expire")
  }

  // Removes the toast at index; a live notification is expired or dismissed at
  // the server depending on reason ("expire", "dismiss", "invoke").
  function removePopup(index: int, reason: string): void {
    if (index < 0 || index >= popupModel.count)
      return
    var entry = popupModel.get(index)
    var originalId = entry ? entry.originalId : -1
    var ref = originalId >= 0 ? liveRefs[originalId] : null
    popupModel.remove(index)
    if (ref) {
      try {
        if (ref.tracked) {
          if (reason === "expire" && typeof ref.expire === "function")
            ref.expire()
          else
            ref.dismiss()
        }
      } catch (e) {
        // Object already torn down by the server — nothing to dismiss.
      }
    }
  }

  // Dismisses every toast on screen.
  function clearPopups(): void {
    while (popupModel.count > 0)
      dismissPopup(0)
  }

  // Opens or closes the notification center through the host shell.
  function toggleCenter(): void {
    if (service.shell && typeof service.shell.toggle === "function")
      service.shell.toggle("araneadev.notifications")
  }

  // Opens the notification center through the host shell.
  function openCenter(): void {
    if (service.shell && typeof service.shell.summon === "function")
      service.shell.summon("araneadev.notifications", "")
  }

  // Tell a still-live sender its notification is gone, then forget it.
  function releaseInboxRef(fileName: string): void {
    var ref = inboxRefs[fileName]
    delete inboxRefs[fileName]
    delete liveSnapshots[fileName]
    if (!ref)
      return
    try {
      if (ref.tracked)
        ref.dismiss()
    } catch (e) {
      // Already torn down by the server.
    }
  }

  // Empties the inbox, dismissing every entry still live at its sender.
  function clearInbox(): void {
    for (var i = 0; i < inbox.model.count; i++)
      releaseInboxRef(inbox.model.get(i).fileName)
    inbox.clear()
  }

  // Removes one inbox entry by file name and dismisses it at its sender.
  function dismissInbox(fileName: string): void {
    releaseInboxRef(fileName)
    inbox.remove(fileName)
  }

  // Removes every inbox entry from one app ("unknown" for an empty app name).
  function dismissGroup(app: string): void {
    var names = []
    for (var i = 0; i < inbox.model.count; i++) {
      var row = inbox.model.get(i)
      if (String(row.app || "unknown") === app)
        names.push(row.fileName)
    }
    for (var j = 0; j < names.length; j++)
      dismissInbox(names[j])
  }

  // Omarchy's argv first, then the sender's own default action while it is
  // still live, then focusing the sending app.
  function invokeInbox(fileName: string): void {
    var entry = inbox.get(fileName)
    if (!entry)
      return
    var argv = NotificationLogic.parseExecArgv(entry.execArgv)
    if (argv)
      Util.execArgv(argv)
    else if (!invokeDefaultAction(inboxRefs[fileName]))
      focusApp(entry)
    dismissInbox(fileName)
  }

  // File name of the newest inbox entry, or "" when the inbox is empty.
  function newestInboxFile(): string {
    return inbox.model.count > 0 ? inbox.model.get(0).fileName : ""
  }

  // Invokes the "default" action of a live notification object.
  // Returns true when one was found and invoked.
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
  // action as an argv vector in the `execArgv` role (see execArgvFromHints).
  // Third-party clients register a libnotify action under the canonical
  // identifier "default" instead; that one only works while the sender is live.
  function invokePopupDefault(index) {
    if (index < 0 || index >= popupModel.count)
      return
    var entry = popupModel.get(index)

    // Run the argv (via Util.execArgv, no shell interpretation). Detached so it
    // outlives the shell, which installer toasts depend on: they restart it.
    var argv = NotificationLogic.parseExecArgv(entry ? entry.execArgv : "")
    if (argv) {
      Util.execArgv(argv)
      removePopup(index, "invoke")
      return
    }
    var ref = entry ? liveRefs[entry.originalId] : null
    var invoked = invokeDefaultAction(ref)
    // Chat apps (Slack, Discord, Vesktop, etc.) rarely register a "default"
    // libnotify action — they just expect clicking the notification to
    // focus their window. Fall back to focusing the sending app by class so
    // that click-to-jump actually works.
    if (!invoked)
      focusApp(entry)
    removePopup(index, "invoke")
  }

  // Try to focus an existing Hyprland window matching the notification's
  // sender. The helper handles case-insensitive class matching.
  function focusApp(entry) {
    if (!entry || !entry.app)
      return
    focusAppProc.command = [service.omarchyPath + "/bin/omarchy-hyprland-focus-app", String(entry.app)]
    focusAppProc.running = true
  }

  Process {
    id: focusAppProc
    running: false
  }

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

  // Debounces a settings write (200 ms); a no-op until settings have loaded.
  function scheduleSettingsSave(): void {
    if (!service.settingsLoaded)
      return
    settingsSaveTimer.restart()
  }

  // True once settingsPath has been read (or found missing); gates writes.
  property bool settingsLoaded: false

  // Applies notifications.json once: hydrates DND and schedules a rewrite when
  // the file still holds legacy history arrays.
  function loadSettings(raw: string): void {
    // FileView can fire onLoaded more than once during startup — the implicit
    // preload when `path` resolves, plus the explicit `settingsFile.reload()`
    // in Component.onCompleted can both end up calling here.
    if (service.settingsLoaded)
      return
    var parsed = NotificationLogic.parseSettings(raw)
    if (parsed.error)
      console.warn("notifications: settings parse failed:", parsed.errorMessage || "")

    if (parsed.dnd !== null && !service.reloadedSettings) {
      service._hydrating = true
      persisted.doNotDisturb = parsed.dnd
      service._hydrating = false
    }

    service.settingsLoaded = true
    // Versions before the history moved into its own directory kept every
    // notification in here. Rewrite once so that dead payload doesn't sit in
    // the file until the next DND toggle happens to clear it.
    if (parsed.legacy)
      service.scheduleSettingsSave()
  }

  // Writes {version: 3, dnd} to settingsPath.
  function flushSettings(): void {
    settingsFile.setText(JSON.stringify({
      version: 3,
      dnd: persisted.doNotDisturb
    }, null, 2) + "\n")
  }

  Component.onDestruction: {
    // A toggle less than 200 ms old would otherwise be lost with the timer.
    if (settingsSaveTimer.running) {
      // Write synchronously: this object is about to go.
      settingsFile.blockWrites = true
      service.flushSettings()
    }
    ServiceBridge.retract(service)
  }

  // Creates one part of the service (Toasts.qml, NotificationDaemon.qml)
  // with this service as its `root`, or null (with a warning) when it cannot load.
  function createPart(file: string): var {
    var component = Qt.createComponent(Qt.resolvedUrl(file))
    if (component.status !== Component.Ready) {
      console.warn("notifications: " + file + " failed to load:", component.errorString())
      return null
    }
    return component.createObject(service, {
      root: service
    })
  }

  Component.onCompleted: {
    if (service.windowEnabled)
      service.toasts = service.createPart("Toasts.qml")
    if (service.serverEnabled)
      service.server = service.createPart("NotificationDaemon.qml")
    // The bar widget (Panel.qml) finds this service here; see ServiceBridge.js.
    ServiceBridge.publish(service)
    Qt.callLater(function () {
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
      if (!service.quietHoursWindow)
        return "off"
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
      if (!fileName)
        return "none"
      service.dismissInbox(fileName)
      return "ok"
    }

    // Open the newest inbox entry (its action or its app).
    function invokeLast(): string {
      var fileName = service.newestInboxFile()
      if (!fileName)
        return "none"
      service.invokeInbox(fileName)
      return "ok"
    }

    // Take a toast off the screen by summary substring, used by the
    // first-run notifications once their action has been clicked.
    function dismiss(summary: string): string {
      var needle = String(summary || "")
      if (!needle)
        return "none"
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

    function ping(): string {
      return "ok"
    }
  }
}
