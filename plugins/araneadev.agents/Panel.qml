// Aranea Agents (araneadev.agents, cloned from omarchy.agents): the bar
// button and dropdown for Claude Code, Codex and Fireworks usage. Stock's
// root logic stays (Main's discovery and watching, the 30 s clock, the IPC
// target, the provider selection that follows the provider id, h/l, r,
// Enter and the up/down scrolling, self-hiding with no usage, sync and the
// bar entry's settings handed to Main). The pure view, AgentsDropdown,
// draws it in the shared keyboard frame from agentsView; AgentsRing on the
// bar button shows the current agent's fullest limit window. Added: the
// keyboard cursor (shown only while the keyboard drives it; the first key
// only reveals it), the Refresh pill's pending state (AgentsLogic), which
// r, Enter, the pill and IPC refresh share, and the mark probe that walks
// the light-twin fallback for the header.
import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui
import "AgentsLogic.js" as AgentsLogic
import "../araneadev.shared" as Aranea

Panel {
  id: root
  moduleName: "omarchy.agents"
  ipcTarget: "omarchy.agents"
  manageIpc: false

  // The popup's background colour, for picking a light or dark mark.
  readonly property color surface: Color.popups.background

  // Stand-in agents for README screenshots (the showcase IPC method,
  // AgentsLogic.parseShowcase); null outside a capture, and cleared
  // whenever the dropdown opens or closes.
  property var agentsShowcase: null
  // The enabled agents that have recorded usage, in Main's discovery order;
  // the stand-ins instead while showcasing.
  readonly property var providers: agentsShowcase ? agentsShowcase : usage.enabledProviders
  // The selection follows the provider, not the slot it happens to sit in: a
  // provider whose first scan lands while the panel is open would otherwise
  // shift the list underneath you and swap out what you were reading.
  property string selectedProviderId: ""
  // The stand-in agent chosen while a showcase is shown, kept apart from
  // selectedProviderId so a capture never moves the user's real choice
  // (AgentsLogic.selectId); "" outside a showcase.
  property string showcaseSelectedId: ""
  // The providers array position of the shown selection (the real one, or
  // the stand-in one while showcasing), or 0 when it is not (yet) among
  // them.
  readonly property int providerIndex: {
    var id = AgentsLogic.selectedId({
      real: selectedProviderId,
      showcase: showcaseSelectedId
    }, !!agentsShowcase)
    for (var i = 0; i < providers.length; i++)
      if (providers[i].providerId === id)
        return i
    return 0
  }
  // The selected provider's record, or null when there are none.
  readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

  // Whether a navigation key has shown the cursor (or a click put it on a
  // pill).
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears
  // it. The view outlines the cursor only then, so the mouse never shows
  // one.
  property bool keyboardCursor: false
  // The Refresh pill's pending state (AgentsLogic.refreshIdle shape): busy
  // from a refresh request until Main's dataRevision moves past the
  // revision frozen at the request, or until refreshTimeoutMs passes.
  property var refreshPending: AgentsLogic.refreshIdle()
  // How long a refresh may stay pending before the pill gives up.
  readonly property int refreshTimeoutMs: 30000
  // Main's pendingUpdateKind as last seen, for notePendingKind.
  property string lastPendingKind: ""

  // Countdowns and "updated" read this instead of Date.now() so the
  // panel keeps telling the truth while it sits open.
  property double nowMs: Date.now()

  // The selected provider's limit windows, normalised to one shape.
  readonly property var limits: limitWindows(provider)
  // The selected provider's per-model token usage, heaviest first.
  readonly property var models: modelRows(provider)
  // The limit window that decides how much room is left.
  readonly property var headline: bindingWindow(provider)
  // The selected provider's prepaid balance ledger, or null.
  readonly property var balance: provider ? (provider.balance || null) : null
  // A prepaid account runs low the way a subscription window fills up: the
  // last 10% of the funded credits lights the same alarm.
  readonly property bool balanceAlarming: !!balance && balance.funded > 0 && balance.remaining / balance.funded <= 0.1
  // Whether the bar button should show its alarm state: a near-full limit
  // window or a near-empty prepaid balance.
  readonly property bool alarming: (!!headline && headline.percent >= 0.9) || balanceAlarming

  // Clamps v between lo and hi.
  function clamp(v, lo, hi) {
    return Math.max(lo, Math.min(hi, v))
  }

  // Selects the provider at index, wrapping around the list.
  function selectProvider(index) {
    if (providers.length === 0)
      return
    var wrapped = ((index % providers.length) + providers.length) % providers.length
    // While showcasing only the stand-in choice moves.
    var next = AgentsLogic.selectId({
      real: selectedProviderId,
      showcase: showcaseSelectedId
    }, !!agentsShowcase, providers[wrapped].providerId)
    selectedProviderId = next.real
    showcaseSelectedId = next.showcase
  }

  // Forces every collector to re-run now, ignoring refreshIntervalSec.
  function refreshNow() {
    usage.refreshAll(true)
  }

  // Offers Main's dataRevision to the pending refresh: idle, it keeps the
  // baseline current for the next request; busy, it lands the refresh, but
  // only once every shown agent's record was rewritten since the request
  // (a fast collector's record alone would stop the pill early). While the
  // forced run is still queued behind another run (stock queues it as
  // pendingUpdateKind "force"), that run's writes never land it; the
  // queued run's start rebases the landing time (notePendingKind). A shown
  // agent whose collector fails skips its write, so the pill pulses for
  // the full refreshTimeoutMs before it settles.
  function noteRecords() {
    if (root.refreshPending.busy && usage.pendingUpdateKind === "force")
      return
    if (root.refreshPending.busy && !AgentsLogic.recordsLandedSince(root.providers.map(root.updatedMsFor), root.refreshPending.startedAt))
      return
    root.refreshPending = AgentsLogic.refreshLanded(root.refreshPending, usage.dataRevision)
  }

  // Main's queued update kind changed: a queued forced run going from
  // "force" to "" has just started, so a pending refresh waits for records
  // newer than now (AgentsLogic.refreshRebase); the 30 s cap still counts
  // from the request.
  function notePendingKind() {
    var kind = String(usage.pendingUpdateKind || "")
    if (root.lastPendingKind === "force" && kind === "")
      root.refreshPending = AgentsLogic.refreshRebase(root.refreshPending, Date.now())
    root.lastPendingKind = kind
  }

  // The one refresh path (r, Enter, the Refresh pill and IPC refresh): marks
  // the refresh pending and runs refreshNow, or does nothing while one is
  // already pending. Refused while showcasing: the stand-ins are display
  // only.
  function requestRefresh() {
    if (root.agentsShowcase)
      return
    var r = AgentsLogic.refreshClick(root.refreshPending, Date.now())
    root.refreshPending = r.state
    if (r.send)
      root.refreshNow()
  }

  // Runs the agent picker and closes the panel; refused while showcasing.
  function launchAgent() {
    if (root.agentsShowcase)
      return
    // The bar is a plain QtObject to qmllint; run() is the bar's own.
    // qmllint disable missing-property
    if (root.bar)
      root.bar.run("omarchy-agent --pick")
    // qmllint enable missing-property
    root.close()
  }

  // ---------------------------------------------------------------- limits
  //
  // Both providers report the same two shapes: a short rolling session window
  // and a long weekly one. Everything below normalizes them into one record so
  // the meters and the hero speak a single language.

  // Claude spells its windows out ("Session (5-hour)"), Codex abbreviates
  // them ("5h window", "30m window"). Both have to land on the same record.
  function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0 || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0
  }

  // The window's duration in milliseconds, parsed from its label; 0 when
  // no span can be read out of it.
  function windowSpanMs(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0)
      return 30 * 24 * 3600 * 1000
    if (windowIsLong(text))
      return 7 * 24 * 3600 * 1000
    var hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/)
    if (hours)
      return Number(hours[1]) * 3600 * 1000
    var minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/)
    if (minutes)
      return Number(minutes[1]) * 60 * 1000
    return 0
  }

  // The window's display title: Monthly, Weekly, Session, or the label
  // itself with its parenthetical trimmed.
  function windowTitle(label) {
    var text = String(label || "").toLowerCase()
    if (text.indexOf("month") >= 0)
      return "Monthly"
    if (windowIsLong(text))
      return "Weekly"
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0)
      return "Session"
    var plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim()
    return plain === "" ? "Limit" : plain
  }

  // A collector that already knows which window a limit belongs to says so,
  // and that beats reading it back out of the label: a model-scoped limit is
  // titled after its model, and a name like "Opus 5 (1M context)" would parse
  // as a one-minute window.
  function limitWindow(label, percent, resetAt, title) {
    return {
      title: String(title || "") !== "" ? String(title) : windowTitle(label),
      percent: Number(percent),
      resetAt: String(resetAt || "")
    }
  }

  // Every limit window on provider p, normalised through limitWindow.
  function limitWindows(p) {
    if (!p)
      return []
    var out = []
    var list = p.limits || []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (percent >= 0)
        out.push(limitWindow(entry.label, percent, entry.resetsAt, entry.title))
    }
    return out
  }

  // The window that decides how much room is left: the fullest one, since
  // that is what stops the next prompt.
  function bindingWindow(p) {
    var windows = limitWindows(p)
    var best = null
    for (var i = 0; i < windows.length; i++) {
      if (!best || windows[i].percent > best.percent)
        best = windows[i]
    }
    return best
  }

  // Milliseconds until window w resets, or -1 when it has no reset time.
  function resetMsFor(w) {
    if (!w || w.resetAt === "")
      return -1
    var ms = new Date(w.resetAt).getTime()
    return isFinite(ms) ? ms - root.nowMs : -1
  }

  // Formats ms as "Xd Yh", "Xh Ym" or "Xm"; "now" when ms is not positive.
  function formatDuration(ms) {
    if (!(ms > 0))
      return "now"
    var minutes = Math.floor(ms / 60000)
    var hours = Math.floor(minutes / 60)
    var days = Math.floor(hours / 24)
    if (days > 0)
      return days + "d " + (hours % 24) + "h"
    if (hours > 0)
      return hours + "h " + (minutes % 60) + "m"
    return Math.max(1, minutes) + "m"
  }

  // ---------------------------------------------------------------- balance
  //
  // Prepaid agents report a credit ledger instead of rate-limit windows: the
  // record's balance object carries remaining, funded, and spent amounts.

  // The symbol or prefix to show before an amount in this currency.
  function currencyPrefix(currency) {
    var code = String(currency || "USD").toUpperCase()
    if (code === "USD")
      return "$"
    if (code === "EUR")
      return "€"
    if (code === "GBP")
      return "£"
    return code + " "
  }

  // Formats value with two decimals and the currency's prefix.
  function formatMoney(value, currency) {
    var amount = Number(value)
    if (!isFinite(amount))
      amount = 0
    return currencyPrefix(currency) + amount.toFixed(2)
  }

  // "spent of funded" detail text for balance b, or "" with no funded amount.
  function balanceDetailText(b) {
    if (!b || !(b.funded > 0))
      return ""
    var text = formatMoney(b.spent, b.currency) + " spent of " + formatMoney(b.funded, b.currency) + " funded"
    if (b.estimated)
      text += " · estimated"
    return text
  }

  // ---------------------------------------------------------------- content

  // The plan you pay for, under the name of the tool it pays for. Limits live
  // in their own section; the hero just says what this is.
  function heroMeta(p) {
    if (!p)
      return ""
    if (String(p.usageStatusText || "") !== "")
      return p.usageStatusText
    var tier = String(p.tierLabel || "")
    if (tier === "")
      return "Subscription"
    return tier.charAt(0).toUpperCase() + tier.slice(1)
  }

  // Local calendar date, recomputed from nowMs so a panel left open across
  // midnight moves the "Today" row with the clock.
  function todayDate() {
    var now = new Date(root.nowMs)
    return now.getFullYear() + "-" + String(now.getMonth() + 1).padStart(2, "0") + "-" + String(now.getDate()).padStart(2, "0")
  }

  // The three-letter weekday name for an ISO date string.
  function dayName(date) {
    var parsed = new Date(String(date || "") + "T00:00:00")
    if (isNaN(parsed.getTime()))
      return String(date || "")
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()]
  }

  // "Today" for the current day, else its weekday name.
  function dayLabel(date, today) {
    if (today)
      return "Today"
    return dayName(date)
  }

  // The hover tooltip for a day row: date and tokens, plus prompts and
  // sessions for today when the provider reports them.
  function dayTooltip(day, today) {
    if (!day)
      return ""
    var parsed = new Date(String(day.date) + "T00:00:00")
    var label = isNaN(parsed.getTime()) ? String(day.date) : dayName(day.date) + " " + (parsed.getMonth() + 1) + "/" + parsed.getDate()
    var text = label + " · " + usage.formatTokenCount(Number(day.messageCount || 0)) + " tokens"
    // Prompt and session counts only exist for today, so they ride along here
    // instead of taking a section of their own. Billing-API agents never
    // count prompts, and "0 prompts" would read as a quiet day, not a gap.
    if (today && provider && provider.hasPromptStats !== false)
      text += " · " + Number(provider.todayPrompts || 0) + " prompts · " + Number(provider.todaySessions || 0) + " sessions"
    return text
  }

  // The busiest day's message count across p's recent days, for scaling
  // the day bars.
  function weekPeak(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = 0
    for (var i = 0; i < days.length; i++)
      peak = Math.max(peak, Number(days[i].messageCount || 0))
    return peak
  }

  // The top 4 models by total tokens on provider p, with their input,
  // output and cache token split.
  function modelRows(p) {
    var usageByModel = p ? (p.modelUsage || {}) : {}
    var rows = []
    for (var id in usageByModel) {
      var bucket = usageByModel[id] || {}
      var input = Number(bucket.inputTokens || 0)
      var output = Number(bucket.outputTokens || 0)
      var cacheRead = Number(bucket.cacheReadInputTokens || 0)
      var cacheWrite = Number(bucket.cacheCreationInputTokens || 0)
      rows.push({
        name: usage.friendlyModelName(id),
        total: input + output + cacheRead + cacheWrite,
        input: input,
        output: output,
        cacheRead: cacheRead,
        cacheWrite: cacheWrite
      })
    }
    rows.sort(function (a, b) {
      return b.total - a.total
    })
    return rows.slice(0, 4)
  }

  // The hover tooltip for a model row: input, output and cache token split.
  function modelTooltip(row) {
    if (!row)
      return ""
    return "In " + usage.formatTokenCount(row.input) + " · out " + usage.formatTokenCount(row.output) + " · cache read " + usage.formatTokenCount(row.cacheRead) + " · cache write " + usage.formatTokenCount(row.cacheWrite)
  }

  // Only speaks up when the numbers cover more than this machine.
  function footerText() {
    if (usage.syncStatusText !== "")
      return usage.syncStatusText
    if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
      return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s")
    return ""
  }

  // Agents that ship a white mark carry an `assets/<id>-light.svg` twin for
  // light surfaces; marks that work on both (Claude's brand-orange) ship one
  // file. The luminance check decides which candidate to try first.
  function colorChannelLuminance(value) {
    var channel = Number(value)
    if (!isFinite(channel))
      return 0
    return channel <= 0.03928 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4)
  }

  // The relative luminance of color, for picking a light or dark mark.
  function colorLuminance(color) {
    return 0.2126 * colorChannelLuminance(color.r) + 0.7152 * colorChannelLuminance(color.g) + 0.0722 * colorChannelLuminance(color.b)
  }

  // Marks resolve by convention, so a new agent's data file needs nothing
  // from this panel: assets/<id>.svg if it ships one, the module's bar glyph
  // if it doesn't.
  function iconCandidatesForProvider(p, surfaceColor) {
    if (!p)
      return []
    var candidates = []
    if (colorLuminance(surfaceColor || Color.background) >= 0.5)
      candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"))
    candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"))
    return candidates
  }

  // ------------------------------------------------------------------ view

  // The mark candidates for the selected provider (iconCandidatesForProvider
  // against the dropdown's surface).
  readonly property var markCandidates: iconCandidatesForProvider(provider, surface)
  // Provider objects are rebuilt on every refresh, which churns the array's
  // identity without changing its content. Restart the fallback walk only
  // when the URLs change: re-pointing source at a URL whose load already
  // failed emits no statusChanged, so an identity-only reset would strand
  // the walker on a missing -light twin.
  readonly property string markCandidatesKey: markCandidates.join("\n")
  // The candidate markProbe is trying.
  property int markCandidateIndex: 0
  onMarkCandidatesKeyChanged: markCandidateIndex = 0

  // The header's mark: the first candidate that loaded, "" for the glyph.
  readonly property string markUrl: markProbe.status === Image.Ready ? String(markProbe.source) : ""

  // The bar ring's fill: the current agent's fullest limit window, -1 with
  // none (a prepaid-only agent draws no ring).
  readonly property real ringFraction: AgentsLogic.ringFraction(ringLimits(limits))
  // The bar ring's tone for ringFraction.
  readonly property string ringTone: AgentsLogic.ringTone(ringFraction)

  // Limit windows W as ringFraction reads them: percent already a 0..1
  // fraction, clamped, since a value above 1 would read as 0..100.
  function ringLimits(w) {
    return (w || []).map(function (entry) {
      return {
        percent: root.clamp(Number(entry.percent), 0, 1)
      }
    })
  }

  // The usage record's write time for provider p in milliseconds, 0 when
  // unknown (a synced-only provider has no local record).
  function updatedMsFor(p) {
    if (!p)
      return 0
    // A stand-in agent carries its own made-up update time.
    if (p.showcaseUpdatedMs !== undefined)
      return Number(p.showcaseUpdatedMs) || 0
    var list = usage.agents || []
    for (var i = 0; i < list.length; i++) {
      var record = list[i] ? list[i].record : null
      if (record && String(record.id || "") === p.providerId) {
        var ms = Date.parse(String(record.updatedAt || ""))
        return isFinite(ms) ? ms : 0
      }
    }
    return 0
  }

  // The fraction of the window's span already elapsed (the pace tick):
  // the span read from the collector's LABEL (else the window's title),
  // the end from window w's reset time; -1 when either is unknown.
  function paceFor(w, label) {
    var span = windowSpanMs(String(label || "") !== "" ? label : (w ? w.title : ""))
    var remainingMs = resetMsFor(w)
    if (!(span > 0) || remainingMs < 0)
      return -1
    return clamp(1 - remainingMs / span, 0, 1)
  }

  // A limit row's key: its title, with "#n" added only when an earlier row
  // in ROWS already took that title.
  function limitKey(rows, title) {
    var key = title
    for (var n = 2; rows.some(function (r) {
      return r.key === key
    }); n++)
      key = title + "#" + n
    return key
  }

  // The view rows for provider p's limit windows, filtered and normalised
  // the way limitWindows does, keeping each entry's label for the pace.
  function limitViewRows(p) {
    var list = p ? (p.limits || []) : []
    var rows = []
    for (var i = 0; i < list.length; i++) {
      var entry = list[i] || {}
      var percent = Number(entry.percent)
      if (!(percent >= 0))
        continue
      var w = limitWindow(entry.label, percent, entry.resetsAt, entry.title)
      var tone = AgentsLogic.ringTone(clamp(w.percent, 0, 1))
      var remainingMs = resetMsFor(w)
      rows.push({
        key: limitKey(rows, w.title),
        label: w.title,
        fraction: clamp(w.percent, 0, 1),
        percent: Math.round(w.percent * 100) + "%",
        tone: tone === "accent" ? "plain" : tone,
        pace: paceFor(w, entry.label),
        resets: remainingMs > 0 ? "Resets in " + formatDuration(remainingMs) : ""
      })
    }
    return rows
  }

  // The view rows for p's recent days, scaled to the busiest one.
  function dayViewRows(p) {
    var days = p ? (p.recentDays || []) : []
    var peak = Math.max(1, weekPeak(p))
    var today = todayDate()
    var rows = []
    for (var i = 0; i < days.length; i++) {
      var day = days[i] || {}
      // By date, not by position: the Claude stats-cache fallback can hand
      // us a window that stops short of today.
      var isToday = String(day.date || "") === today
      var count = Number(day.messageCount || 0)
      rows.push({
        key: AgentsLogic.dayKey(day),
        label: dayLabel(day.date, isToday),
        fraction: clamp(count / peak, 0, 1),
        value: usage.formatTokenCount(count),
        today: isToday,
        detail: dayTooltip(day, isToday)
      })
    }
    return rows
  }

  // The view rows for the model list, scaled to the heaviest model (the
  // same scale-to-peak the day rows use).
  function modelViewRows(list) {
    var top = list.length > 0 ? Math.max(1, list[0].total) : 1
    return list.map(function (row) {
      return {
        key: AgentsLogic.modelKey(row),
        label: row.name,
        fraction: root.clamp(row.total / top, 0, 1),
        value: usage.formatTokenCount(row.total),
        detail: root.modelTooltip(row)
      }
    })
  }

  // The balance view object, or null with no prepaid ledger.
  function balanceView(b) {
    if (!b)
      return null
    return {
      remaining: formatMoney(b.remaining, b.currency),
      // The meter shows what is left, not what is used: a prepaid account
      // drains toward empty rather than filling toward a cap.
      fraction: b.funded > 0 ? clamp(b.remaining / b.funded, 0, 1) : -1,
      detail: balanceDetailText(b),
      tone: balanceAlarming ? "urgent" : "plain"
    }
  }

  // The header caption: an auth or endpoint problem replaces the plan
  // (heroMeta), else the plan with the record's "updated HH:MM".
  function heroCaption(p) {
    if (!p)
      return ""
    if (String(p.usageStatusText || "") !== "")
      return heroMeta(p)
    return AgentsLogic.updatedCaption(heroMeta(p), updatedMsFor(p))
  }

  // The key hint under the dropdown.
  function keyHint() {
    var dot = " " + String.fromCodePoint(0xB7) + " "
    var arrows = String.fromCodePoint(0x2191, 0x2193)
    var parts = []
    if (providers.length > 1)
      parts.push("h/l agent")
    parts.push("enter/r refresh", arrows + " scroll")
    return parts.join(dot)
  }

  // Everything the Aranea view draws (AgentsDropdown.view).
  readonly property var agentsView: ({
      hero: {
        mark: markUrl,
        glyph: String.fromCodePoint(0xF16A3),
        title: provider ? provider.providerName : "",
        caption: heroCaption(provider),
        problem: provider && String(provider.usageStatusText || "") !== "" ? String(provider.authHelpText || "") : ""
      },
      refresh: {
        busy: !!refreshPending.busy
      },
      agents: providers.map(function (p, i) {
        return {
          key: AgentsLogic.providerKey(p),
          label: p.providerName,
          selected: i === root.providerIndex
        }
      }),
      limits: limitViewRows(provider),
      balance: balanceView(balance),
      days: dayViewRows(provider),
      models: modelViewRows(models),
      // The sync footer speaks for the real machine, never for stand-ins.
      footer: agentsShowcase ? "" : footerText(),
      empty: providers.length === 0,
      cursor: {
        active: cursorActive && keyboardCursor,
        section: providers.length > 1 ? "agents" : "refresh",
        index: providers.length > 1 ? providerIndex : 0
      },
      keyHint: keyHint()
    })

  // Carries out one AgentsDropdown action. Every action comes from the
  // pointer, so each one hands the cursor back from the keyboard, except a
  // hover: that is only the control's own fill and never moves the cursor
  // or hides the outline.
  function handleAction(name, arg) {
    if (name === "hover")
      return
    keyboardCursor = false
    if (name === "refresh") {
      requestRefresh()
      return
    }
    if (name === "selectAgent") {
      // Keyed: the provider at that index must still be the one the view
      // showed there.
      if (!arg || !providers[arg.index] || providers[arg.index].providerId !== arg.key)
        return
      cursorActive = true
      selectProvider(arg.index)
    }
  }

  // Nothing to report, nothing in the bar: Bar.qml collapses a slot whose item
  // is invisible, so the icon appears the moment the first scan finds usage and
  // stays away entirely on a machine that has never run either CLI.
  visible: providers.length > 0
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onProviderIndexChanged: dropdown.scrollToTop()
  onOpenedChanged: {
    // Stand-ins never carry over into an open or past a close; the real
    // selection was never touched.
    agentsShowcase = null
    showcaseSelectedId = AgentsLogic.showcaseSelectionCleared({
      real: selectedProviderId,
      showcase: showcaseSelectedId
    }).showcase
    if (!opened)
      return
    cursorActive = false
    keyboardCursor = false
    nowMs = Date.now()
    dropdown.scrollToTop()
    usage.refreshLimits()
  }

  // The refresh landing baseline is taken here, before any click, so the
  // first refresh waits for a real change rather than the first revision.
  Component.onCompleted: root.noteRecords()

  Main {
    id: usage
    settings: root.settings
    onDataRevisionChanged: root.noteRecords()
    onPendingUpdateKindChanged: root.notePendingKind()
  }

  // Cheap enough to keep running: it only re-evaluates text bindings, and a
  // stale "resets in 2h" on a panel that is open is worse than a timer.
  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  // Gives up on a refresh that never lands (refreshTimeoutMs), checked once
  // a second while one is pending.
  Timer {
    interval: 1000
    running: !!root.refreshPending.busy
    repeat: true
    onTriggered: root.refreshPending = AgentsLogic.refreshTimeout(root.refreshPending, Date.now(), root.refreshTimeoutMs)
  }

  // Walks markCandidates until one loads; never shown (the header loads
  // the same URL).
  Image {
    id: markProbe
    visible: false
    source: root.markCandidateIndex < root.markCandidates.length ? root.markCandidates[root.markCandidateIndex] : ""
    sourceSize.width: Style.font.display * 2
    sourceSize.height: Style.font.display * 2
    // Advancing source from inside its own status change trips the
    // binding-loop detector; defer the step one tick.
    onStatusChanged: if (status === Image.Error && root.markCandidateIndex < root.markCandidates.length)
      Qt.callLater(function () {
        root.markCandidateIndex++
      })
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void {
      root.open()
    }
    function close(): void {
      root.close()
    }
    function show(): void {
      root.open()
    }
    function hide(): void {
      root.close()
    }
    function toggle(): void {
      root.toggle()
    }
    function refresh(): string {
      if (root.agentsShowcase)
        return "refused"
      root.requestRefresh()
      return "ok"
    }
    // Screenshot stand-ins (scripts/capture-screenshots): SHOWCASEJSON, a
    // JSON object (AgentsLogic.parseShowcase), replaces the agents with
    // made-up ones (plans, limits, days, models, a balance) and selects
    // the first (without touching the real selection), until the dropdown closes; while it is closed the answer
    // is "closed" and nothing is set. Display only: no collector runs, and
    // refresh and the agent picker are refused meanwhile.
    function showcase(showcaseJson: string): string {
      var call = AgentsLogic.showcaseCall(root.opened, showcaseJson, Date.now())
      if (call.showcase !== null) {
        root.agentsShowcase = call.showcase
        root.showcaseSelectedId = call.showcase[0].providerId
        // A capture never shows a real refresh's pulse.
        root.refreshPending = AgentsLogic.refreshCancel(root.refreshPending)
        root.nowMs = Date.now()
      }
      return call.answer
    }
    function next(): string {
      root.selectProvider(root.providerIndex + 1)
      return "ok"
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: String.fromCodePoint(0xF16A3)
    active: root.alarming
    onPressed: function (buttonCode) {
      root.keyboardCursor = false
      if (buttonCode === Qt.RightButton)
        root.launchAgent()
      else if (buttonCode === Qt.MiddleButton)
        root.selectProvider(root.providerIndex + 1)
      else
        root.toggle()
    }

    // Display only, drawn over the glyph slot: no layout change and no
    // pointer input, so every click still reaches the button.
    AgentsRing {
      anchors.centerIn: parent
      width: Math.min(Style.space(22), button.width, button.height)
      height: width
      fraction: root.ringFraction
      tone: root.ringTone
    }
  }

  // The Aranea view in the shared keyboard frame. The view pins the header
  // and the switch and scrolls the rest itself within maxHeight (stock's
  // 640 cap, or less on a short screen), so the frame only sizes to it.
  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after mouse use only reveals the
      // cursor where it is.
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      if (dx !== 0)
        root.selectProvider(root.providerIndex + dx)
      if (dy !== 0)
        dropdown.scrollBy(dy)
    }
    onActivateRequested: {
      dropdown.disarmPointer()
      if (!root.cursorActive || !root.keyboardCursor) {
        root.cursorActive = true
        root.keyboardCursor = true
        return
      }
      root.requestRefresh()
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      if (t === "r" || t === "R") {
        root.keyboardCursor = true
        root.requestRefresh()
      }
    }

    Item {
      anchors.fill: parent
      clip: true

      AgentsDropdown {
        id: dropdown
        width: parent.width
        maxHeight: panel.availableCardHeight > 0 ? Math.min(Style.space(640), panel.availableCardHeight - panel.verticalContentInset) : Style.space(640)
        view: root.agentsView
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
