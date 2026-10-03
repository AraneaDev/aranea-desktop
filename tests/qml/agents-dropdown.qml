// The Aranea agents view and bar ring, in a real window with real pointer
// events: agent pills report their key, and a choice whose pill changed
// underneath (a re-sort, including one between press and release) is
// refused; a re-sort stamps the layout and a click inside the settle window
// is refused, then accepted; the mint outline follows only the keyboard
// cursor and pointer hover never draws one; the Refresh pill pulses and
// ignores clicks while busy; rebuilding the arrays with equal keys keeps
// every pill and row delegate and does not stamp; limits, days, models and
// the balance draw strand bars and a limit's pace draws its tick; warning
// tones tint the percent text; the problem card, the empty text and the
// scroll cap; hovering today or a model shows its detail and reports the
// hover; and the ring hides at tone "none" and takes its colour per tone.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.agents" as Agents
import "plugins/araneadev.shared" as Shared

ShellRoot {
  QmlTest {
    id: t
  }

  // Actions reported by view, as [name, arg], in emission order.
  property var actions: []
  // The layout stamp a step compares against.
  property real stampBefore: 0
  // Pill delegates captured before a rebuild.
  property var pillsBefore: []
  // The pointer's resting point for the hover checks.
  property var hoverPoint: null

  // Synthesizes pointer events (TestCase's mouse helpers), never run as a
  // test.
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  // An agent pill: KEY, LABEL and whether it is SELECTED.
  function agent(key, label, selected) {
    return {
      key: key,
      label: label,
      selected: selected
    }
  }

  // The three stand-in agents, Claude Code selected.
  readonly property var agentRows: [agent("claude", "Claude Code", true), agent("codex", "Codex", false), agent("fireworks", "Fireworks", false)]

  // A view with AGENTS, the refresh BUSY or not, and CURSOR.
  function viewOf(agents, busy, cursor) {
    return {
      hero: {
        mark: "",
        glyph: "x",
        title: "Claude Code",
        caption: "Max 20x · updated 23:58",
        problem: ""
      },
      refresh: {
        busy: busy
      },
      agents: agents,
      limits: [
        {
          key: "session",
          label: "Session",
          fraction: 0.14,
          percent: "14%",
          tone: "plain",
          pace: 0.4,
          resets: "Resets in 3h 0m"
        },
        {
          key: "weekly",
          label: "Weekly",
          fraction: 0.92,
          percent: "92%",
          tone: "attention",
          pace: -1,
          resets: "Resets in 2d 20h"
        },
        {
          key: "opus",
          label: "Opus 5",
          fraction: 0.97,
          percent: "97%",
          tone: "urgent",
          pace: 0.9,
          resets: ""
        }
      ],
      balance: {
        remaining: "$12.40",
        fraction: 0.3,
        detail: "$28.60 spent of $41.00 funded",
        tone: "plain"
      },
      days: [
        {
          key: "2026-10-02",
          label: "Fri",
          fraction: 0.98,
          value: "864.5M",
          today: false,
          detail: "Fri 10/2 · 864.5M tokens"
        },
        {
          key: "2026-10-03",
          label: "Sat",
          fraction: 0.24,
          value: "207.1M",
          today: false,
          detail: "Sat 10/3 · 207.1M tokens"
        },
        {
          key: "2026-10-04",
          label: "Today",
          fraction: 0.6,
          value: "525.9M",
          today: true,
          detail: "Sun 10/4 · 525.9M tokens · 41 prompts · 3 sessions"
        }
      ],
      models: [
        {
          key: "Sonnet 5",
          label: "Sonnet 5",
          fraction: 1,
          value: "2.8B",
          detail: "In 1.2M · out 3.4M · cache read 2.7B · cache write 80.1M"
        },
        {
          key: "Opus 5",
          label: "Opus 5",
          fraction: 0.3,
          value: "840.0M",
          detail: "In 0.4M · out 1.0M · cache read 800.0M · cache write 38.6M"
        }
      ],
      empty: false,
      footer: "Merged from 2 devices",
      cursor: cursor || {
        active: false,
        section: "",
        index: -1
      },
      keyHint: "h/l agent · r refresh · ↑↓ scroll · tab next"
    }
  }

  // A deep copy of V (equal content, new objects), as a refresh rebuilds it.
  function copyOf(v) {
    return JSON.parse(JSON.stringify(v))
  }

  // Actions other than hover.
  function nonHover() {
    return actions.filter(function (a) {
      return a[0] !== "hover"
    })
  }

  // Whether an action NAME with ARG (compared as JSON) was reported.
  function reported(name, arg) {
    var want = JSON.stringify([name, arg])
    return actions.some(function (a) {
      return JSON.stringify(a) === want
    })
  }

  // The agent pills, in order.
  function pills() {
    return t.findChildren(t.findChild(view, "agentSwitch"), "agentPill")
  }

  // Whether ITEM's keyboard outline is lit.
  function outlined(item) {
    var outline = t.findChild(item, "cursorOutline")
    return outline !== null && outline.border.width > 0
  }

  // Rows of the section named NAME.
  function rowsOf(name) {
    return t.findChildren(t.findChild(view, name), "usageRow")
  }

  // Runs STEPS ([delay, fn] pairs) one after another, then finishes.
  function run(steps) {
    if (steps.length === 0) {
      t.done()
      return
    }
    t.step(steps[0][0], function () {
      steps[0][1]()
      run(steps.slice(1))
    })
  }

  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 1000
    visible: true

    Agents.AgentsDropdown {
      id: view
      width: 380
      maxHeight: 2000
      view: viewOf(agentRows, false)
      onAction: function (name, arg) {
        actions.push([name, arg])
      }
    }
  }

  Agents.AgentsRing {
    id: ringNone
    fraction: -1
    tone: "none"
  }
  Agents.AgentsRing {
    id: ringCalm
    fraction: 0.14
    tone: "accent"
  }
  Agents.AgentsRing {
    id: ringWarn
    fraction: 0.82
    tone: "attention"
  }
  Agents.AgentsRing {
    id: ringFull
    fraction: 0.97
    tone: "urgent"
  }

  Component.onCompleted: run([[400, function () {
        // ---------- Keyed pills ----------
        var p = pills()
        t.equal(p.length, 3, "one pill per agent")
        t.check(p[0].selected && !p[1].selected && !p[2].selected, "the current agent's pill is selected")
        actions = []
        pointer.mouseClick(p[1])
        t.check(reported("selectAgent", {
          index: 1,
          key: "codex"
        }), "a settled pill click reports the agent with its key")

        // A re-sort: Fireworks moves to the front.
        actions = []
        stampBefore = view.layoutChangedAt
        view.view = viewOf([agentRows[2], agentRows[0], agentRows[1]], false)
        t.check(view.layoutChangedAt > stampBefore, "a re-sort of the agents stamps the layout")
        t.check(pills()[0] === p[0], "the re-sort keeps the pill delegates")
        view.keyedAction("selectAgent", view.view.agents, 0, "claude")
        t.equal(nonHover().length, 0, "a keyed choice whose pill changed underneath is refused")
        view.keyedAction("selectAgent", view.view.agents, 1, "claude")
        t.check(reported("selectAgent", {
          index: 1,
          key: "claude"
        }), "the same key at its new pill is accepted")
        actions = []
        pointer.mouseClick(pills()[2])
        t.equal(nonHover().length, 0, "a click right after the re-sort is refused")
      }], [60, function () {
        pointer.mouseClick(pills()[2])
        t.equal(nonHover().length, 0, "and still refused inside the settle window")
      }], [350, function () {
        pointer.mouseClick(pills()[2])
        t.check(reported("selectAgent", {
          index: 2,
          key: "codex"
        }), "a settled click after the re-sort reports the new pill's key")

        // A press, then a re-sort before the release.
        actions = []
        pointer.mousePress(pills()[0])
        view.view = viewOf(agentRows, false)
      }], [350, function () {
        pointer.mouseRelease(pills()[0])
        t.equal(nonHover().length, 0, "a release on a pill that changed since the press is refused")

        // ---------- Settle window ----------
        actions = []
        view.noteLayoutChange()
        pointer.mouseClick(pills()[1])
        pointer.mouseClick(t.findChild(view, "refreshPill"))
        t.equal(nonHover().length, 0, "clicks right after a stamp are refused (pill and Refresh)")
      }], [350, function () {
        pointer.mouseClick(pills()[1])
        pointer.mouseClick(t.findChild(view, "refreshPill"))
        t.check(reported("selectAgent", {
          index: 1,
          key: "codex"
        }), "a settled pill click is accepted")
        t.check(reported("refresh", null), "a settled Refresh click refreshes")

        // ---------- Refresh busy ----------
        actions = []
        view.view = viewOf(agentRows, true)
        var refresh = t.findChild(view, "refreshPill")
        t.check(refresh.busy && refresh.text.indexOf("Refreshing") === 0, "a refresh in flight shows Refreshing at once")
        t.check(t.findChild(refresh, "busyPulse").running, "and pulses")
        pointer.mouseClick(refresh)
        refresh.activate()
        t.equal(nonHover().length, 0, "the busy pill ignores clicks")
        view.view = viewOf(agentRows, false)
        t.check(!refresh.busy && refresh.text === "Refresh" && !t.findChild(refresh, "busyPulse").running, "landing stops the pulse")

        // ---------- Outline keyboard-only ----------
        view.disarmPointer()
        var pill1 = pills()[1]
        hoverPoint = pill1.mapToItem(view, pill1.width / 2, pill1.height / 2)
        actions = []
        pointer.mouseMove(view, hoverPoint.x, hoverPoint.y)
      }], [80, function () {
        pointer.mouseMove(view, hoverPoint.x + 3, hoverPoint.y)
      }], [80, function () {
        t.check(reported("hover", {
          section: "agents",
          index: 1
        }), "a real move onto a pill reports hover")
        t.check(pills().every(function (p) {
          return !outlined(p)
        }) && !outlined(t.findChild(view, "refreshPill")), "pointer hover never draws an outline")
        view.view = viewOf(agentRows, false, {
          active: false,
          section: "agents",
          index: 1
        })
        t.check(!outlined(pills()[1]), "an inactive cursor draws no outline")
        view.view = viewOf(agentRows, false, {
          active: true,
          section: "agents",
          index: 1
        })
        t.check(outlined(pills()[1]) && !outlined(pills()[0]) && !outlined(t.findChild(view, "refreshPill")), "the keyboard cursor outlines exactly its pill")
        view.view = viewOf(agentRows, false, {
          active: true,
          section: "refresh",
          index: 0
        })
        t.check(outlined(t.findChild(view, "refreshPill")) && pills().every(function (p) {
          return !outlined(p)
        }), "the keyboard cursor on Refresh outlines the Refresh pill")
        view.view = viewOf(agentRows, false)

        // ---------- Stable rows ----------
        pillsBefore = pills()
        var limitsBefore = t.findChildren(view, "limitRow")
        var daysBefore = rowsOf("daysSection")
        var modelsBefore = rowsOf("modelsSection")
        stampBefore = view.layoutChangedAt
        view.view = copyOf(viewOf(agentRows, false))
        t.equal(view.layoutChangedAt, stampBefore, "equal arrays rebuilt do not stamp")
        var same = function (a, b) {
          return a.length === b.length && a.length > 0 && a.every(function (x, i) {
            return x === b[i]
          })
        }
        t.check(same(pills(), pillsBefore), "equal agents rebuilt keep the pills")
        t.check(same(t.findChildren(view, "limitRow"), limitsBefore), "equal limits rebuilt keep the rows")
        t.check(same(rowsOf("daysSection"), daysBefore), "equal days rebuilt keep the rows")
        t.check(same(rowsOf("modelsSection"), modelsBefore), "equal models rebuilt keep the rows")

        // ---------- Strand bars and the pace tick ----------
        var limitBars = t.findChildren(view, "limitBar")
        t.equal(limitBars.length, 3, "one strand bar per limit")
        t.check(limitBars.every(function (b) {
          var fill = t.findChild(b, "filamentBarFill")
          return fill !== null && fill.visible && fill.width > 0 && Qt.colorEqual(fill.gradient.stops[0].color, Shared.DesignTokens.accent) && Qt.colorEqual(fill.gradient.stops[1].color, Shared.DesignTokens.strandEnd)
        }), "every limit bar draws its mint to violet strand")
        t.check(Math.abs(t.findChild(limitBars[0], "filamentBarFill").width - limitBars[0].width * 0.14) < 0.5, "a limit bar lights its fraction")
        var tick = t.findChild(limitBars[0], "filamentBarPace")
        t.check(tick.visible && Math.abs(tick.x + tick.width / 2 - limitBars[0].width * 0.4) < 0.5, "a limit with a pace draws its tick at the pace")
        t.check(!t.findChild(limitBars[1], "filamentBarPace").visible, "a limit without a pace draws none")
        var dayBars = t.findChildren(t.findChild(view, "daysSection"), "usageBar")
        var modelBars = t.findChildren(t.findChild(view, "modelsSection"), "usageBar")
        t.check(dayBars.length === 3 && dayBars.every(function (b) {
          return t.findChild(b, "filamentBarFill").width > 0
        }), "every day draws a strand bar")
        t.check(modelBars.length === 2 && Math.abs(t.findChild(modelBars[0], "filamentBarFill").width - modelBars[0].width) < 0.5, "every model draws a strand bar, the heaviest full")
        var balanceBar = t.findChild(view, "balanceBar")
        t.check(balanceBar.visible && Math.abs(t.findChild(balanceBar, "filamentBarFill").width - balanceBar.width * 0.3) < 0.5, "the balance draws what is left as a strand")
        t.equal(t.findChild(view, "balanceDetail").text, "$28.60 spent of $41.00 funded", "the balance shows funded versus spent")

        // ---------- Tones, today, problem card, footer ----------
        var percents = t.findChildren(view, "limitPercent")
        t.check(Qt.colorEqual(percents[0].color, Shared.DesignTokens.foreground), "a calm limit's percent is plain")
        t.check(Qt.colorEqual(percents[1].color, Shared.DesignTokens.attention), "a limit near the cap tints its percent amber")
        t.check(Qt.colorEqual(percents[2].color, Shared.DesignTokens.urgent), "a limit at the cap tints its percent urgent")
        var resets = t.findChildren(view, "limitResets")
        t.check(resets[0].visible && resets[0].text === "Resets in 3h 0m" && !resets[2].visible, "a limit shows its countdown, and one with no reset hides it")
        var dayLabels = t.findChildren(t.findChild(view, "daysSection"), "usageLabel")
        t.check(dayLabels[2].font.bold && !dayLabels[0].font.bold, "today is bold, other days are not")
        t.check(!t.findChild(view, "problemCard").visible, "no problem, no card")
        var withProblem = viewOf(agentRows, false)
        withProblem.hero.problem = "Run claude to sign in again."
        view.view = withProblem
        t.check(t.findChild(view, "problemCard").visible && t.findChild(view, "problemText").text === "Run claude to sign in again.", "an auth problem shows its card")
        t.check(t.findChild(view, "footerText").visible, "the sync footer shows")
        var noBalance = viewOf(agentRows, false)
        noBalance.balance = null
        view.view = noBalance
        t.check(!t.findChild(view, "balanceSection").visible, "no balance, no BALANCE section")

        // ---------- Empty, single agent, scroll cap ----------
        var single = viewOf([agentRows[0]], false)
        stampBefore = view.layoutChangedAt
        view.view = single
        t.check(!t.findChild(view, "agentSwitch").visible, "one agent shows no switch")
        t.check(view.layoutChangedAt > stampBefore, "the switch hiding stamps the layout")
        view.view = {
          empty: true,
          agents: [],
          keyHint: ""
        }
        t.check(t.findChild(view, "emptyText").visible && !t.findChild(view, "agentsHeader").visible, "no agents shows the empty text and no header")
        view.view = viewOf(agentRows, false)
        view.maxHeight = 300
      }], [50, function () {
        var scroll = view.scroll
        t.check(scroll.height < scroll.contentHeight && view.height <= 300 + 1, "the sections scroll within the height cap")
        view.scrollBy(1)
        t.check(scroll.contentY > 0, "a scroll step moves the sections")
        view.scrollBy(1000)
        t.check(Math.abs(scroll.contentY - (scroll.contentHeight - scroll.height)) < 0.5, "scrolling stops at the end")
        view.scrollToTop()
        t.equal(scroll.contentY, 0, "and returns to the top")
        view.maxHeight = 2000

        // ---------- Hover detail on today ----------
        view.disarmPointer()
        actions = []
        var today = rowsOf("daysSection")[2]
        hoverPoint = today.mapToItem(view, today.width / 2, today.height / 2)
        pointer.mouseMove(view, hoverPoint.x, hoverPoint.y)
      }], [80, function () {
        pointer.mouseMove(view, hoverPoint.x + 3, hoverPoint.y)
      }], [80, function () {
        var today = rowsOf("daysSection")[2]
        t.check(reported("hover", {
          section: "days",
          index: 2
        }), "a real move onto today reports hover")
        t.check(today.detailShown && t.findChild(today, "usageTip").text === "Sun 10/4 · 525.9M tokens · 41 prompts · 3 sessions", "hovering today shows its prompts and sessions")
        t.check(!rowsOf("daysSection")[0].detailShown, "other rows keep their detail hidden")
        var model = rowsOf("modelsSection")[0]
        hoverPoint = model.mapToItem(view, model.width / 2, model.height / 2)
        actions = []
        pointer.mouseMove(view, hoverPoint.x, hoverPoint.y)
      }], [80, function () {
        pointer.mouseMove(view, hoverPoint.x + 3, hoverPoint.y)
      }], [80, function () {
        var model = rowsOf("modelsSection")[0]
        t.check(reported("hover", {
          section: "models",
          index: 0
        }), "a real move onto a model reports hover")
        t.check(model.detailShown && t.findChild(model, "usageTip").text.indexOf("cache read") > 0, "hovering a model shows its input/output/cache split")
        t.check(!rowsOf("daysSection")[2].detailShown, "leaving today hides its detail")

        // ---------- Ring ----------
        t.check(!ringNone.visible, "tone none draws no ring")
        t.check(ringCalm.visible && Qt.colorEqual(ringCalm.ringColor, Shared.DesignTokens.accent), "a calm ring is the accent")
        t.check(ringWarn.visible && Qt.colorEqual(ringWarn.ringColor, Shared.DesignTokens.attention), "a ring near the cap is amber")
        t.check(ringFull.visible && Qt.colorEqual(ringFull.ringColor, Shared.DesignTokens.urgent), "a ring at the cap is urgent")
        t.equal(ringCalm.drawn, 0.14, "the ring fills with its fraction")
        ringCalm.fraction = 1.4
        t.equal(ringCalm.drawn, 1, "a fraction past 1 fills the ring once")
        ringCalm.tone = "none"
        t.check(!ringCalm.visible, "the ring hides when its tone turns none")
        t.check(t.findChild(ringFull, "ringCanvas") !== null, "the ring draws on a canvas")
      }]])
}
