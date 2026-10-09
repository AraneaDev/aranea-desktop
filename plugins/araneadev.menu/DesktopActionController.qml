// Persistent quick-action orchestration; search presentation never owns service state.
import QtQuick
import "DesktopActionRecords.js" as Records
import "DesktopActionState.js" as State
import "../araneadev.audio/AudioBridge.js" as AudioBridge
import "../araneadev.notifications/ServiceBridge.js" as NotificationBridge

Item {
  id: actions
  // Active root search owns only observation subscriptions, not mutation lifetime.
  property bool active: false
  // Whether production owner discovery and filesystem observations may run.
  property bool observationsEnabled: true
  // Inert fixtures explicitly refuse all dispatch and owner reads.
  property bool showcaseActive: false
  // Accepted display-only owner snapshot, never used for dispatch.
  property var showcaseSnapshot: null
  // Real feedback restored when a capture ends.
  property var showcaseSavedState: null
  // Live notification owner; fixtures may supply the same narrow contract.
  property var notificationOwner: null
  // Shared default-device owner published by the audio plugin.
  property var audioOwner: null
  // Audio owner currently leased by this active search.
  property var leasedAudioOwner: null
  // Notification owner associated with the in-flight request.
  property var requestedNotificationOwner: null
  // Audio owner associated with the in-flight request.
  property var requestedAudioOwner: null
  // Desired manual preference, distinct from quiet hours.
  property bool dndTarget: false
  // Maximum notification preference confirmation time.
  property int dndTimeout: 3000
  // Immutable per-family generation and feedback maps.
  property var actionState: State.idle()
  // Latest published action records, retaining original searchable context.
  property var records: []
  // Publication revision observed by the search source controller.
  property int revision: 0
  // Keyed feedback projection used only for presentation.
  readonly property var feedback: actionState.feedback
  // Persistent wallpaper process owner, replaceable at the boundary if needed.
  property var wallpaperOwner: wallpaperController
  // Wallpaper boundary exposed to isolated fixtures without opening any window.
  readonly property alias wallpaper: wallpaperController

  DesktopWallpaperActions {
    id: wallpaperController
    active: actions.active
    observationsEnabled: actions.observationsEnabled
    showcaseActive: actions.showcaseActive
  }
  onFeedbackChanged: refreshNow()
  onNotificationOwnerChanged: {
    if (actionState.pending.dnd && (!notificationOwner || notificationOwner !== requestedNotificationOwner))
      settle("dnd", actionState.pending.dnd.requestId, false, "Notifications are no longer available")
    requestRefresh()
  }
  onAudioOwnerChanged: {
    if (actionState.pending.audio && (!audioOwner || audioOwner !== requestedAudioOwner))
      settle("audio", actionState.pending.audio.requestId, false, "Audio output is no longer available")
    syncLease()
    requestRefresh()
  }
  onActiveChanged: {
    if (active) {
      discoverOwners()
      requestRefresh()
    } else {
      refreshTimer.stop()
    }
    syncLease()
  }
  onShowcaseActiveChanged: syncLease()
  Component.onDestruction: if (leasedAudioOwner)
    leasedAudioOwner.releaseSearch()

  // Reacquire publication slots while active, without overwriting fixture owners.
  function discoverOwners(): void {
    if (!observationsEnabled || showcaseActive)
      return
    notificationOwner = NotificationBridge.current()
    audioOwner = AudioBridge.current()
  }
  // Balance one search lease across visibility and owner replacement.
  function syncLease(): void {
    if (leasedAudioOwner && (!active || leasedAudioOwner !== audioOwner || showcaseActive)) {
      leasedAudioOwner.releaseSearch()
      leasedAudioOwner = null
    }
    if (active && !showcaseActive && audioOwner && leasedAudioOwner !== audioOwner) {
      audioOwner.acquireSearch()
      leasedAudioOwner = audioOwner
    }
  }
  // Read authoritative owner values immediately before activation.
  function readSnapshot(): var {
    if (showcaseActive)
      return showcaseSnapshot || ({})
    if (!showcaseActive)
      discoverOwners()
    return {
      dnd: notificationOwner ? {
        available: true,
        enabled: notificationOwner.doNotDisturb,
        quietHours: notificationOwner.quietHours
      } : {
        available: false
      },
      audio: audioOwner ? audioOwner.snapshot() : {
        available: false
      },
      wallpaper: wallpaperOwner ? wallpaperOwner.snapshot() : {
        available: false
      }
    }
  }
  // Fresh selectable identities for activation, independent of coalesced rows.
  function currentRecords(): var {
    return Records.actionRecords(readSnapshot())
  }
  // Install an inert capture only when no actual mutation can be obscured.
  function beginShowcase(snapshot, feedback): string {
    if (Object.keys(actionState.pending).length || (wallpaperOwner && (wallpaperOwner.pending || wallpaperOwner.commandBusy)))
      return "busy"
    if (!snapshot || typeof snapshot !== "object" || Array.isArray(snapshot))
      return "invalid"
    var rows = Records.actionRecords(snapshot)
    var safeFeedback = ({})
    rows.forEach(function (row) {
      var value = feedback && feedback[row.key]
      if (value && ["pending", "confirmed", "failed"].indexOf(value.status) >= 0)
        safeFeedback[row.key] = {
          status: value.status,
          message: typeof value.message === "string" ? value.message : ""
        }
    })
    if (!showcaseActive)
      showcaseSavedState = actionState
    showcaseActive = true
    showcaseSnapshot = snapshot
    actionState = {
      sequence: actionState.sequence,
      pending: ({}),
      feedback: safeFeedback
    }
    records = rows
    revision += 1
    return "ok"
  }
  // Restore observed owner state without issuing a mutation.
  function endShowcase(): void {
    if (!showcaseActive)
      return
    if (showcaseSavedState)
      actionState = showcaseSavedState
    showcaseSavedState = null
    showcaseSnapshot = null
    showcaseActive = false
    refreshNow()
  }
  // Publish typed records and preserve transient feedback separately from matching.
  function refreshNow(): void {
    if (showcaseActive)
      return
    records = Records.actionRecords(readSnapshot())
    revision += 1
  }
  // Coalesce owner changes only while the current search needs new rows.
  function requestRefresh(): void {
    if (active && !showcaseActive && !refreshTimer.running)
      refreshTimer.start()
  }
  // Settle the matching request and discard duplicate or obsolete outcomes.
  function settle(family: string, requestId: string, ok: bool, message: string): void {
    actionState = State.complete(actionState, family, requestId, ok, message)
    if (family === "dnd" && !actionState.pending.dnd) {
      dndDeadline.stop()
      requestedNotificationOwner = null
    }
    if (family === "audio" && !actionState.pending.audio)
      requestedAudioOwner = null
  }
  // Observe the requested manual preference, including synchronous owner echoes.
  function confirmDnd(): void {
    var pending = actionState.pending.dnd
    if (pending && requestedNotificationOwner && requestedNotificationOwner === notificationOwner && notificationOwner.doNotDisturb === dndTarget)
      settle("dnd", pending.requestId, true, "")
  }
  // Activate only a freshly resolvable typed action; never use a cached row label.
  function activate(key: string): bool {
    if (!active || showcaseActive)
      return false
    var row = Records.actionRecords(readSnapshot()).find(function (record) {
      return record.key === key
    })
    if (!row)
      return false
    var id = row.target.actionId
    var family = id === "dnd" ? "dnd" : id.indexOf("audio:") === 0 ? "audio" : id.indexOf("wallpaper:") === 0 ? "wallpaper" : ""
    if (!family)
      return false
    var next = State.begin(actionState, family, key, Date.now())
    if (!next.accepted)
      return false
    // Set owner identities before state publication, which can synchronously refresh.
    if (family === "dnd") {
      requestedNotificationOwner = notificationOwner
      dndTarget = !notificationOwner.doNotDisturb
    } else if (family === "audio") {
      requestedAudioOwner = audioOwner
    }
    actionState = next.state
    try {
      if (family === "dnd") {
        dndDeadline.restart()
        notificationOwner.setDoNotDisturb(dndTarget)
        confirmDnd()
      } else if (family === "audio") {
        if (!audioOwner.requestOutput(id.slice(6), next.requestId))
          settle(family, next.requestId, false, "Audio output is busy or no longer available")
      } else if (!wallpaperOwner.request(id.slice(10), next.requestId)) {
        settle(family, next.requestId, false, "Previous wallpaper change is still running")
      }
    } catch (error) {
      settle(family, next.requestId, false, family === "dnd" ? "Could not change Do not disturb" : family === "audio" ? "Could not change audio output" : "Could not apply wallpaper")
    }
    return true
  }
  Timer {
    id: refreshTimer
    interval: 100
    onTriggered: actions.refreshNow()
  }
  Timer {
    interval: 1000
    repeat: true
    running: actions.active && actions.observationsEnabled && !actions.showcaseActive
    onTriggered: actions.discoverOwners()
  }
  Timer {
    id: dndDeadline
    interval: actions.dndTimeout
    onTriggered: if (actions.actionState.pending.dnd)
      actions.settle("dnd", actions.actionState.pending.dnd.requestId, false, "Timed out changing Do not disturb")
  }
  Connections {
    target: actions.notificationOwner
    enabled: actions.active || !!actions.actionState.pending.dnd
    function onDoNotDisturbChanged() {
      actions.confirmDnd()
      actions.requestRefresh()
    }
    function onQuietHoursChanged() {
      actions.requestRefresh()
    }
  }
  Connections {
    target: actions.audioOwner
    enabled: actions.active || !!actions.actionState.pending.audio
    function onSnapshotChanged() {
      actions.requestRefresh()
    }
    function onOutputCompleted(id, ok, message) {
      actions.settle("audio", id, ok, message)
    }
  }
  Connections {
    target: actions.wallpaperOwner
    enabled: actions.active || !!actions.actionState.pending.wallpaper
    function onSnapshotChanged() {
      actions.requestRefresh()
    }
    function onCompleted(id, ok, message) {
      actions.settle("wallpaper", id, ok, message)
    }
  }
}
