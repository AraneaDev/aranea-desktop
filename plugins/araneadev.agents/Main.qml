// Aranea Agents (araneadev.agents, cloned from omarchy.agents): discovery,
// watching and cross-device sync for agent usage records. Stock's logic
// stays unchanged; Panel.qml draws it in the Aranea dropdown.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import "AgentFleetAggregation.js" as AgentFleetAggregation

// The display side of agent usage. All extraction lives behind
// omarchy-agent-usage-update, which writes one JSON record per agent into
// the usage directory; this file only discovers those records, watches them
// for changes, and optionally merges snapshots synced from other machines.
Item {
  id: root
  visible: false

  // The bar entry's settings object (providers, refreshIntervalSec, sync*).
  property var settings: ({})

  // The user's home directory, read once from the environment.
  readonly property string home: Quickshell.env("HOME") || ""
  // The directory holding one usage JSON file per agent.
  readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/omarchy/agents/usage"

  // ------------------------------------------------------------- discovery

  // The agent ids found in usageDir, from the last rescan.
  property var agentIds: []
  // The live Agent watchers, one per agentIds entry.
  property var agents: []
  // Bumped whenever any agent's record changes, so bindings that read
  // agents' records recompute.
  property int dataRevision: 0

  Process {
    id: listProcess
    running: false
    command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyAgentListing(text)
    }
  }

  // Re-lists usageDir for *.json files, unless a listing is already running.
  function rescanAgents() {
    if (!listProcess.running)
      listProcess.running = true
  }

  // Parses the find output into agentIds, replacing it only when the
  // sorted id list actually changed.
  function applyAgentListing(output) {
    var ids = []
    var lines = String(output || "").split("\n")
    for (let i = 0; i < lines.length; i++) {
      let name = lines[i].trim()
      if (name.slice(-5) === ".json")
        ids.push(name.slice(0, -5))
    }
    ids.sort()
    // Same list, same objects: reassigning the model would tear down every
    // FileView just to build identical ones.
    if (JSON.stringify(ids) !== JSON.stringify(agentIds))
      agentIds = ids
  }

  Instantiator {
    id: agentInstantiator
    model: root.agentIds

    delegate: Agent {
      id: agentDelegate
      required property var modelData
      agentId: agentDelegate.modelData
      path: root.usageDir + "/" + agentDelegate.modelData + ".json"
      onRecordChanged: root.recordsChanged()
    }

    onObjectAdded: (index, object) => root.rebuildAgents()
    onObjectRemoved: (index, object) => root.rebuildAgents()
  }

  // Rebuilds agents from the live Instantiator objects, keyed by agentIds.
  function rebuildAgents() {
    var result = []
    for (let i = 0; i < agentInstantiator.count; i++) {
      let agent = agentInstantiator.objectAt(i)
      if (agent)
        result.push(agent)
    }
    agents = result
    recordsChanged()
  }

  // Runs whenever any agent's record changes: bumps dataRevision and
  // schedules the retry timer and a sync.
  function recordsChanged() {
    dataRevision++
    scheduleLimitsRetry()
    scheduleSync()
  }

  // A collector that could not reach its limits endpoint at all (typically
  // the seconds after login before the network is up) writes retryAdvised
  // into its record. Honor it with one sooner try instead of waiting out the
  // full refresh interval; a run that reaches the endpoint clears the flag.
  // Only the advising agents rerun, so an outage at one provider does not
  // put every other collector on a 30-second treadmill.
  property var retryAgentIds: []

  Timer {
    id: limitsRetry
    interval: 30000
    repeat: false
    onTriggered: root.runUpdate("limits", root.retryAgentIds)
  }

  // Collects the agents whose record asked for a sooner retry and restarts
  // (or stops) the retry timer for them.
  function scheduleLimitsRetry() {
    var advising = []
    for (let i = 0; i < agents.length; i++) {
      let record = agents[i] ? agents[i].record : null
      if (record && record.retryAdvised === true && providerEnabled(String(record.id || "")))
        advising.push(String(record.id))
    }
    retryAgentIds = advising
    if (advising.length > 0)
      limitsRetry.restart()
    else
      limitsRetry.stop()
  }

  Component.onCompleted: {
    rescanAgents()
    if (syncConfigured())
      scheduleSync()
  }

  // -------------------------------------------------------------- refresh

  // How often the refresh timer reruns the collectors, clamped to 30s.
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)))
  // The kind of update queued behind a run already in progress, or "".
  property string pendingUpdateKind: ""

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate("normal")
  }

  Process {
    id: updateProcess
    running: false
    // Quickshell's ExitStatus type is not visible to qmllint.
    // qmllint disable signal-handler-parameters
    onExited: {
      root.rescanAgents()
      if (root.pendingUpdateKind !== "") {
        let kind = root.pendingUpdateKind
        root.pendingUpdateKind = ""
        root.runUpdate(kind)
      }
    }
    // qmllint enable signal-handler-parameters

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "")
        console.warn("agents", text.trim())
    }
  }

  // The omarchy-agent-usage-update argv for this kind, limited to agentIds
  // when given and excluding any provider the settings disable.
  function updateCommand(kind, agentIds) {
    var command = ["omarchy-agent-usage-update"]
    if (kind === "force")
      command.push("--force")
    if (kind === "limits")
      command.push("--limits-only")
    var providers = settings && settings.providers ? settings.providers : {}
    for (let id in providers) {
      if (providers[id] && providers[id].enabled === false)
        command.push("--except", id)
    }
    if (agentIds) {
      for (let i = 0; i < agentIds.length; i++)
        command.push(agentIds[i])
    }
    return command
  }

  // Runs the collectors for kind, queuing behind a run already in progress.
  function runUpdate(kind, agentIds) {
    if (updateProcess.running) {
      // Collapse queued requests to one full rerun; a forced refresh outranks
      // the cheaper kinds it might have been queued behind.
      if (kind === "force" || root.pendingUpdateKind === "")
        root.pendingUpdateKind = kind
      return
    }
    updateProcess.command = updateCommand(kind, agentIds)
    updateProcess.running = true
  }

  // IPC alias for refreshAll(true).
  function refresh() {
    refreshAll(true)
  }
  // Runs every collector, forcing a full rescan when force is true.
  function refreshAll(force) {
    runUpdate(force === true ? "force" : "normal")
  }

  // Opening the panel wants the numbers that go stale on the wire, not
  // another walk over every transcript on disk: the collectors reuse their
  // recent scans in this mode.
  function refreshLimits() {
    runUpdate("limits")
  }

  // ------------------------------------------------------------- providers

  // An agent earns a place in the bar and the panel by being switched on in
  // settings and having actually produced numbers, locally or on a synced
  // device. With nothing to show, the whole module collapses out of the bar
  // rather than sitting there dimmed.
  property var enabledProviders: {
    var rev = dataRevision
    var syncRev = syncRevision
    var result = []
    var localIds = {}
    for (let i = 0; i < agents.length; i++) {
      let record = agents[i] ? agents[i].record : null
      if (!record || !record.id)
        continue
      let id = String(record.id)
      localIds[id] = true
      if (!providerEnabled(id))
        continue
      let display = displayProvider(record)
      if (providerHasData(display))
        result.push(display)
    }
    // An agent that only ever ran on another machine has no local record, but
    // its synced numbers still deserve a tab. Rate limits stay blank; they
    // are per-account and never travel.
    var syncedProviders = syncConfigured() && aggregateData && aggregateData.providers ? aggregateData.providers : {}
    for (let syncedId in syncedProviders) {
      if (localIds[syncedId] || !providerEnabled(syncedId))
        continue
      let stats = syncedProviders[syncedId] || {}
      let syncedDisplay = displayProvider({
        id: syncedId,
        name: stats.providerName || syncedId
      })
      if (providerHasData(syncedDisplay))
        result.push(syncedDisplay)
    }
    return result
  }

  // Whether provider id is switched on in settings (default on).
  function providerEnabled(id) {
    if (!settings || !settings.providers || !settings.providers[id])
      return true
    return settings.providers[id].enabled !== false
  }

  // All-time keeps a quiet day from hiding an agent; today's counts admit a
  // machine whose only source is history.jsonl, which knows nothing older.
  function providerHasData(p) {
    return numberValue(p.totalPrompts) > 0 || numberValue(p.totalSessions) > 0 || numberValue(p.activeDays) > 0 || numberValue(p.todayPrompts) > 0 || numberValue(p.todaySessions) > 0 || (p.limits && p.limits.length > 0) || !!p.balance
  }

  // A prepaid agent's credit ledger. Like rate limits, the balance is
  // per-account and never merged across devices.
  function balanceValue(raw) {
    if (!raw || typeof raw !== "object")
      return null
    var remaining = Number(raw.remaining)
    var funded = Number(raw.funded)
    if (!isFinite(remaining) || remaining < 0)
      return null
    return {
      remaining: remaining,
      funded: isFinite(funded) && funded > 0 ? funded : 0,
      spent: Math.max(0, Number(raw.spent) || 0),
      currency: String(raw.currency || "USD"),
      estimated: raw.estimated === true
    }
  }

  // The view record for an agent: its local record, with any fields a
  // synced snapshot carries swapped in.
  function displayProvider(record) {
    var stats = syncedStatsFor(String(record.id))
    var synced = !!stats
    var deviceCount = synced ? Number(stats.deviceCount || aggregateData.deviceCount || 0) : 0

    return {
      providerId: String(record.id),
      providerName: String(record.name || record.id),
      ready: record.ready === true || synced,
      usageStatusText: String(record.usageStatusText || ""),
      authHelpText: String(record.authHelpText || ""),

      // Rate limits and balances stay per-account and are never merged
      // across devices.
      limits: Array.isArray(record.limits) ? record.limits : [],
      tierLabel: String(record.tierLabel || ""),
      balance: balanceValue(record.balance),
      todayPrompts: synced ? numberValue(stats.todayPrompts) : numberValue(record.todayPrompts),
      todaySessions: synced ? numberValue(stats.todaySessions) : numberValue(record.todaySessions),
      todayTotalTokens: synced ? numberValue(stats.todayTotalTokens) : numberValue(record.todayTotalTokens),
      todayTokensByModel: synced ? (stats.todayTokensByModel || ({})) : (record.todayTokensByModel || ({})),
      recentDays: synced ? (stats.recentDays || []) : (record.recentDays || []),
      totalPrompts: synced ? numberValue(stats.totalPrompts) : numberValue(record.totalPrompts),
      totalSessions: synced ? numberValue(stats.totalSessions) : numberValue(record.totalSessions),
      activeDays: synced ? numberValue(stats.activeDays) : numberValue(record.activeDays),
      modelUsage: synced ? (stats.modelUsage || ({})) : (record.modelUsage || ({})),
      hasLocalStats: synced ? (stats.hasLocalStats !== false) : (record.hasLocalStats !== false),
      hasPromptStats: synced ? (stats.hasPromptStats !== false) : (record.hasPromptStats !== false),
      syncEnabled: synced,
      syncDeviceCount: deviceCount,
      syncUpdatedAt: aggregateData && aggregateData.updatedAt ? aggregateData.updatedAt : ""
    }
  }

  // Reads settings[name], or fallback when unset.
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ------------------------------------------------------------------ sync

  // The raw syncMode setting (falls back to the older syncEnabled key).
  property var syncModeSetting: setting("syncMode", setting("syncEnabled", false))
  // Whether cross-device sync is on, parsed from syncModeSetting.
  property bool syncEnabled: parseSyncEnabled(syncModeSetting)
  // The configured sync folder, before expansion.
  property string syncDir: String(setting("syncDir", ""))
  // The configured snapshot file name, before defaulting.
  property string syncFileName: String(setting("syncFileName", ""))
  // The configured device id, before defaulting.
  property string syncDeviceId: String(setting("syncDeviceId", ""))
  // This machine's hostname, read from /etc/hostname.
  property string detectedHostname: ""
  // syncDir with ~ and $HOME expanded.
  readonly property string syncEffectiveDir: expandPath(syncDir)
  // The snapshot file name actually used, defaulted and sanitised.
  readonly property string syncEffectiveFileName: safeSnapshotFileName(syncFileName, syncDeviceId)
  // The device id actually used, defaulted and sanitised.
  readonly property string syncEffectiveDeviceId: safeDeviceId(syncDeviceId || syncEffectiveFileName.replace(/\.json$/i, ""))
  // Where this machine's snapshot is read and written; a disabled path
  // when sync is off, so nothing is created by accident.
  readonly property string syncSnapshotPath: syncConfigured() ? syncEffectiveDir + "/" + syncEffectiveFileName : home + "/.cache/omarchy/agents-disabled.json"
  // The merged snapshot data from every synced device, or {}.
  property var aggregateData: ({})
  // Bumped whenever aggregateData is replaced.
  property int syncRevision: 0
  // Whether a sync (mkdir, write or scan) is currently running.
  property bool syncRunning: false
  // Whether another sync was requested while one was already running.
  property bool syncRequestedWhileRunning: false
  // The last sync error or status message, or "".
  property string syncStatusText: ""
  // aggregateData's updatedAtMs, or 0 when there is none.
  property double aggregateUpdatedAtMs: aggregateData && aggregateData.updatedAtMs ? Number(aggregateData.updatedAtMs) : 0

  onSyncEnabledChanged: syncSettingsChanged()
  onSyncDirChanged: syncSettingsChanged()
  onSyncFileNameChanged: if (syncConfigured())
    scheduleSync()
  onSyncDeviceIdChanged: if (syncConfigured())
    scheduleSync()

  Timer {
    id: syncDebounce
    interval: 1000
    repeat: false
    onTriggered: root.runSync()
  }

  Process {
    id: syncMkdirProcess
    running: false
    onRunningChanged: root.updateSyncRunning()
    // Quickshell's ExitStatus type is not visible to qmllint.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        if (root.syncConfigured())
          root.syncStatusText = "Usage sync mkdir failed"
        root.finishSyncRun()
        return
      }
      root.writeSyncSnapshot()
    }
    // qmllint enable signal-handler-parameters
  }

  Process {
    id: syncScanProcess
    running: false
    onRunningChanged: root.updateSyncRunning()
    // Quickshell's ExitStatus type is not visible to qmllint.
    // qmllint disable signal-handler-parameters
    onExited: function (exitCode) {
      if (exitCode !== 0 && root.syncConfigured())
        root.syncStatusText = "Usage sync scan failed"
      root.finishSyncRun()
    }
    // qmllint enable signal-handler-parameters

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.parseSyncScanOutput(text)
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: if (text.trim() !== "")
        console.warn("agents/sync", text.trim())
    }
  }

  FileView {
    id: syncSnapshotFile
    path: root.syncSnapshotPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  FileView {
    id: hostnameFile
    path: "/etc/hostname"
    watchChanges: false
    printErrors: false
    onLoaded: root.detectedHostname = String(text() || "").trim()
  }

  // Parses syncMode/syncEnabled's many accepted spellings into a bool.
  function parseSyncEnabled(value) {
    if (value === true)
      return true
    var text = String(value || "").trim().toLowerCase()
    return text === "on" || text === "enabled" || text === "true" || text === "yes" || text === "1"
  }

  // Whether sync is on and a folder is actually set.
  function syncConfigured() {
    return root.syncEnabled === true && String(root.syncDir || "").trim() !== ""
  }

  // Reacts to sync settings changing: schedules a sync, or clears the
  // aggregate and stops pending sync work when sync just turned off.
  function syncSettingsChanged() {
    if (syncConfigured()) {
      scheduleSync()
    } else {
      syncDebounce.stop()
      syncRequestedWhileRunning = false
      aggregateData = ({})
      syncStatusText = ""
      syncRevision++
    }
  }

  // Recomputes syncRunning from the mkdir and scan processes.
  function updateSyncRunning() {
    root.syncRunning = syncMkdirProcess.running || syncScanProcess.running
  }

  // Debounces a sync run, when sync is configured.
  function scheduleSync() {
    if (!syncConfigured())
      return
    syncDebounce.restart()
  }

  // Starts a sync pass (mkdir, then write, then scan), or defers it when
  // one is already running.
  function runSync() {
    if (!syncConfigured())
      return
    if (root.syncRunning) {
      syncRequestedWhileRunning = true
      return
    }

    syncRequestedWhileRunning = false
    syncStatusText = ""
    syncMkdirProcess.command = ["mkdir", "-p", root.syncEffectiveDir]
    syncMkdirProcess.running = true
  }

  // Writes this machine's snapshot, then starts the scan for peers' snapshots.
  function writeSyncSnapshot() {
    if (!syncConfigured()) {
      finishSyncRun()
      return
    }
    syncSnapshotFile.setText(JSON.stringify(localSnapshot(), null, 2) + "\n")
    Qt.callLater(root.startSyncScan)
  }

  // Reads every snapshot file in the sync folder in one process.
  function startSyncScan() {
    if (!syncConfigured()) {
      finishSyncRun()
      return
    }
    var script = "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done"
    syncScanProcess.command = ["bash", "-c", script, root.syncEffectiveDir]
    syncScanProcess.running = true
  }

  // Marks the sync pass done, rerunning it if one was requested meanwhile.
  function finishSyncRun() {
    if (syncRequestedWhileRunning && syncConfigured()) {
      syncRequestedWhileRunning = false
      scheduleSync()
    }
  }

  // Expands ~, ~/ and $HOME/ in path, or treats a relative path as
  // relative to home.
  function expandPath(path) {
    var value = String(path || "").trim()
    if (value === "")
      return ""
    if (value === "~")
      return home
    if (value.indexOf("~/") === 0)
      return home + value.substring(1)
    if (value.indexOf("$HOME/") === 0)
      return home + value.substring(5)
    if (value.charAt(0) !== "/")
      return home + "/" + value
    return value
  }

  // A filesystem-safe device id, defaulted from the hostname/user when raw
  // is blank.
  function safeDeviceId(raw) {
    var value = String(raw || "").trim()
    if (value === "")
      value = Quickshell.env("HOSTNAME") || root.detectedHostname || Quickshell.env("HOST") || Quickshell.env("USER") || "device"
    value = value.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "")
    if (value === "")
      value = "device"
    return value.length > 80 ? value.substring(0, 80) : value
  }

  // A filesystem-safe ".json" snapshot file name, defaulted from the
  // device id when rawFileName is blank.
  function safeSnapshotFileName(rawFileName, rawDeviceId) {
    var value = String(rawFileName || "").trim()
    if (value === "")
      value = safeDeviceId(rawDeviceId) + ".json"
    value = value.split("/").pop().replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "")
    if (value === "")
      value = safeDeviceId(rawDeviceId) + ".json"
    if (!/\.json$/i.test(value))
      value += ".json"
    return value.length > 100 ? value.substring(0, 95) + ".json" : value
  }

  // Splits the scan's ===path===...=== EOM === stream into parsed snapshot
  // objects and merges them into aggregateData.
  function parseSyncScanOutput(output) {
    var lines = String(output || "").split("\n")
    var snapshots = []
    var currentPath = ""
    var currentJson = []

    function flush() {
      if (currentPath === "")
        return
      var raw = currentJson.join("\n").trim()
      try {
        let parsed = JSON.parse(raw)
        if (parsed && parsed.providers)
          snapshots.push(parsed)
      } catch (e) {
        console.warn("agents/sync", "Ignoring bad snapshot", currentPath, e)
      }
      currentPath = ""
      currentJson = []
    }

    for (let i = 0; i < lines.length; i++) {
      let line = lines[i]
      let start = line.match(/^===(.+)===$/)
      if (start && line !== "=== EOM ===") {
        flush()
        currentPath = start[1]
        currentJson = []
        continue
      }
      if (line === "=== EOM ===") {
        flush()
        continue
      }
      if (currentPath !== "")
        currentJson.push(line)
    }
    flush()

    aggregateData = aggregateSnapshots(snapshots)
    syncStatusText = ""
    syncRevision++
  }

  // A deep JSON clone of value, or fallback when value is unset or
  // unserialisable.
  function cloneValue(value, fallback) {
    if (value === undefined || value === null)
      return fallback
    try {
      return JSON.parse(JSON.stringify(value))
    } catch (e) {
      return fallback
    }
  }

  // value as a finite rounded number, or 0.
  function numberValue(value) {
    var n = Number(value || 0)
    return isFinite(n) ? Math.round(n) : 0
  }

  // date as a local-calendar "YYYY-MM-DD" string.
  function dateString(date) {
    var y = date.getFullYear()
    var m = String(date.getMonth() + 1).padStart(2, "0")
    var d = String(date.getDate()).padStart(2, "0")
    return y + "-" + m + "-" + d
  }

  // The last 7 calendar dates (today last), as "YYYY-MM-DD" strings.
  function recentDateStrings() {
    var result = []
    for (let offset = 6; offset >= 0; offset--) {
      let date = new Date()
      date.setDate(date.getDate() - offset)
      result.push(dateString(date))
    }
    return result
  }

  // Supplies runtime identity, calendar and clock inputs to the pure reducer.
  function aggregateSnapshots(snapshots) {
    var normalized = []
    for (let i = 0; i < snapshots.length; i++) {
      let snapshot = snapshots[i]
      normalized.push({
        deviceId: safeDeviceId(snapshot.deviceId || "device"),
        providers: snapshot.providers
      })
    }
    return AgentFleetAggregation.aggregateSnapshots(normalized, recentDateStrings(), new Date().toISOString(), Date.now())
  }

  // Snapshots keep the field names older Omarchy versions wrote, so a fleet
  // of machines on mixed versions still merges cleanly in both directions.
  function providerSnapshot(record) {
    return {
      providerId: String(record.id),
      providerName: String(record.name || record.id),
      ready: record.ready === true,
      hasLocalStats: record.hasLocalStats !== false,
      hasPromptStats: record.hasPromptStats !== false,
      scope: String(record.scope || "device"),
      todayPrompts: numberValue(record.todayPrompts),
      todaySessions: numberValue(record.todaySessions),
      todayTotalTokens: numberValue(record.todayTotalTokens),
      todayTokensByModel: cloneValue(record.todayTokensByModel, ({})),
      recentDays: cloneValue(record.recentDays, []),
      totalPrompts: numberValue(record.totalPrompts),
      totalSessions: numberValue(record.totalSessions),
      activeDays: numberValue(record.activeDays),
      activeDates: cloneValue(record.activeDates, []),
      modelUsage: cloneValue(record.modelUsage, ({}))
    }
  }

  // This machine's snapshot: one providerSnapshot per enabled agent with a
  // record.
  function localSnapshot() {
    var providerMap = {}
    for (let i = 0; i < agents.length; i++) {
      let record = agents[i] ? agents[i].record : null
      if (!record || !record.id)
        continue
      if (!providerEnabled(String(record.id)))
        continue
      providerMap[String(record.id)] = providerSnapshot(record)
    }
    return {
      schemaVersion: 1,
      deviceId: syncEffectiveDeviceId,
      updatedAt: new Date().toISOString(),
      providers: providerMap
    }
  }

  // The merged stats for providerId from aggregateData, or null when sync
  // is off or there are none.
  function syncedStatsFor(providerId) {
    var rev = syncRevision
    if (!syncConfigured() || !aggregateData || !aggregateData.providers)
      return null
    return aggregateData.providers[providerId] || null
  }

  // ---------------------------------------------------------------- format

  // Formats n with a B/M/K suffix above 1000, else as-is.
  function formatTokenCount(n) {
    if (n === undefined || n === null)
      return "0"
    if (n >= 1e9)
      return (n / 1e9).toFixed(1) + "B"
    if (n >= 1e6)
      return (n / 1e6).toFixed(1) + "M"
    if (n >= 1e3)
      return (n / 1e3).toFixed(1) + "K"
    return String(n)
  }

  // Title-cases word, with GPT and DeepSeek spelled out.
  function modelWordCase(word) {
    if (word === "gpt")
      return "GPT"
    if (word === "deepseek")
      return "DeepSeek"
    return word.charAt(0).toUpperCase() + word.slice(1)
  }

  // Model ids arrive hyphenated with the version split across segments
  // (`claude-opus-4-8`, `gpt-5.6-sol`). Rejoin the numeric run into one
  // version and title-case the words around it.
  function friendlyModelName(id) {
    if (!id)
      return "Unknown"
    var name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "")
    var parts = name.split("-")
    var words = []
    var version = []
    for (let i = 0; i < parts.length; i++) {
      let part = parts[i]
      if (part === "")
        continue
      if (/^\d/.test(part)) {
        version.push(part)
        continue
      }
      if (version.length > 0) {
        words.push(version.join("."))
        version = []
      }
      words.push(modelWordCase(part))
    }
    if (version.length > 0)
      words.push(version.join("."))
    return words.length > 0 ? words.join(" ") : "Unknown"
  }
}
