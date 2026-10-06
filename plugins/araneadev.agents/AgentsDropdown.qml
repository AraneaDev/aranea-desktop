// The Aranea agents dropdown's view: the header (tool mark, tool, plan and
// "updated" caption, Refresh pill), the agent switch, then, scrolling
// together inside a Flickable (objectName "agentsScroll") so the whole
// dropdown stays within maxHeight (stock's 640 cap), the optional history
// and models and sync footer. Errors, balance and limits remain above it,
// and the empty text; a key hint closes it. Drawn from one plain view
// object (Panel's agents view) and reporting every user action through a
// single action signal. No usage records here, so tests drive it with
// fixtures.
//
// Anything that moves the pills under a still pointer without the pointer
// moving (the agents changing or re-sorting, the switch or the header
// showing or hiding, the header changing height) stamps layoutChangedAt,
// which the pills read through pointerGate: a click within 300 ms of it is
// ignored unless the pointer has really moved there since. Agent choices carry the pill's key (the
// provider id) and are never sent when the pill at that index holds
// another key. The keyboard outline only follows view.cursor; pointer
// hover never draws one, it only reports a hover action.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by the panel:
  //   hero {mark, glyph, title, caption, problem}; refresh {busy};
  //   agents [{key, label, selected}];
  //   limits [{key, label, fraction, percent, tone, pace, resets}];
  //   balance {remaining, fraction, detail, tone} or null;
  //   days [{key, label, fraction, value, today, detail}];
  //   models [{key, label, fraction, value, detail}];
  //   footer (optional sync text); empty; cursor {active, section, index};
  //   details {historyExpanded, modelsExpanded}; keyHint.
  property var view: ({})
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // The hero object from the view, or a blank one.
  readonly property var hero: view && view.hero ? view.hero : ({
      mark: "",
      glyph: "",
      title: "",
      caption: "",
      problem: ""
    })
  // Cap on the whole dropdown's height (stock's 640); the sections below
  // the switch scroll past it.
  property real maxHeight: Style.space(640)
  // Filters synthetic hover from pills and rows moving under a still
  // pointer (e.g. the agents list changing underneath the cursor).
  readonly property alias pointerGate: gate
  // The scroll area, for the host's up/down keys and tests.
  readonly property alias scroll: agentsScroll
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // The agent keys joined, so an equal list rebuilt by the host does not
  // stamp the layout.
  readonly property string agentKeys: dropdown.joinKeys(dropdown.view.agents)
  // Whether the header and the switch show; each moves the pills.
  readonly property string pinnedShown: String(!dropdown.view.empty) + String((dropdown.view.agents || []).length > 1)

  // Emitted for every user action, NAME with its ARG:
  //   refresh (null): the Refresh pill was clicked while idle;
  //   selectAgent ({index, key}): an agent pill was chosen; it carries the
  //     pill's key (the provider id) as the view held it, and is never
  //     sent when the pill's key changed underneath;
  //   toggleDetails ({section: "history" | "models"}): disclosure activation;
  //   hover ({section, index}): the pointer really moved onto the Refresh
  //     pill (section "refresh", index 0), an agent pill ("agents"), a day
  //     row ("days") or a model row ("models").
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the pills without the pointer.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // ROWS' keys joined by newlines, "" for none.
  function joinKeys(rows) {
    return (rows || []).map(function (r) {
      return r && r.key !== undefined ? String(r.key) : ""
    }).join("\n")
  }

  // Reports NAME for row INDEX of ROWS holding KEY, refused when that row
  // no longer carries KEY (the list changed underneath).
  function keyedAction(name, rows, index, key) {
    // Defence in depth: pointer clicks across a re-sort are really stopped
    // by the layout stamp, the pills' settle and Panel's own key check.
    var row = (rows || [])[index]
    if (!row || String(row.key) !== key)
      return
    dropdown.action(name, {
      index: index,
      key: key
    })
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // Cursor index for SECTION: the view's index there, else -2 (none).
  function cursorIn(section) {
    return dropdown.cursor.active && dropdown.cursor.section === section ? dropdown.cursor.index : -2
  }

  // Scrolls the sections by STEPS rows (the up/down keys), clamped to the
  // content.
  function scrollBy(steps) {
    var limit = Math.max(0, agentsScroll.contentHeight - agentsScroll.height)
    agentsScroll.contentY = Math.max(0, Math.min(limit, agentsScroll.contentY + steps * Style.space(56)))
  }

  // Scrolls the sections back to the top (opening, switching agent).
  function scrollToTop() {
    agentsScroll.contentY = 0
    primaryScroll.contentY = 0
  }

  // Shared budget after identity, provider selection and the fixed hint.
  readonly property real bodyBudget: Math.max(0, maxHeight - (header.visible ? header.height + spacing : 0) - (agentSwitch.visible ? agentSwitch.height + spacing : 0) - (keyHint.visible ? keyHint.implicitHeight + spacing : 0))
  // Reserve collapsed heading space, so expansion never crowds out decisions.
  readonly property real detailReserve: Math.min(scrollColumn.implicitHeight, (historyDisclosure.visible ? historyDisclosure.children[0].height : 0) + (modelsDisclosure.visible ? modelsDisclosure.children[0].height : 0) + (footerText.visible ? footerText.implicitHeight : 0) + Math.max(0, Number(historyDisclosure.visible) + Number(modelsDisclosure.visible) + Number(footerText.visible) - 1) * spacing)

  // Keep focused headings visible after expansion or a smaller height budget.
  function ensureCursorVisible() {
    if (!dropdown.cursor.active || dropdown.cursor.section !== "details")
      return
    var section = dropdown.cursor.index === 0 ? historyDisclosure : modelsDisclosure
    if (!section.visible)
      return
    var heading = section.children[0]
    var top = heading.mapToItem(scrollColumn, 0, 0).y
    var bottom = top + heading.height
    var limit = Math.max(0, agentsScroll.contentHeight - agentsScroll.height)
    if (top < agentsScroll.contentY)
      agentsScroll.contentY = Math.max(0, top)
    else if (bottom > agentsScroll.contentY + agentsScroll.height)
      agentsScroll.contentY = Math.min(limit, bottom - agentsScroll.height)
  }

  // Equal refreshes keep the stamp; actual detail changes settle pointer input.
  readonly property string detailLayout: String(!!(view.details && view.details.historyExpanded)) + String(!!(view.details && view.details.modelsExpanded)) + joinKeys(view.days) + joinKeys(view.models)
  onDetailLayoutChanged: {
    dropdown.noteLayoutChange()
    Qt.callLater(dropdown.ensureCursorVisible)
  }
  onCursorChanged: Qt.callLater(dropdown.ensureCursorVisible)
  spacing: Style.space(16)
  onAgentKeysChanged: dropdown.noteLayoutChange()
  onPinnedShownChanged: dropdown.noteLayoutChange()

  AgentsHeader {
    id: header
    width: parent.width
    visible: !dropdown.view.empty
    markSource: dropdown.hero.mark || ""
    glyph: dropdown.hero.glyph || ""
    title: dropdown.hero.title || ""
    caption: dropdown.hero.caption || ""
    busy: !!(dropdown.view.refresh && dropdown.view.refresh.busy)
    hasCursor: dropdown.cursorIn("refresh") >= 0
    pointerGate: dropdown.pointerGate
    // A taller or shorter header (a mark loading, a caption change) moves
    // the pills below it as surely as showing or hiding it does.
    onHeightChanged: dropdown.noteLayoutChange()
    onRefreshRequested: dropdown.action("refresh", null)
    onEntered: dropdown.action("hover", {
      section: "refresh",
      index: 0
    })
  }
  AgentsSwitch {
    id: agentSwitch
    objectName: "agentSwitch"
    width: parent.width
    agents: dropdown.view.agents || []
    cursor: dropdown.cursorIn("agents")
    pointerGate: dropdown.pointerGate
    onChosen: function (index, key) {
      dropdown.keyedAction("selectAgent", dropdown.view.agents, index, key)
    }
    onPillHovered: function (index) {
      dropdown.action("hover", {
        section: "agents",
        index: index
      })
    }
  }
  // Primary state stays above optional telemetry. Only unusually long errors
  // or limit lists need their own fallback viewport on constrained screens.
  Flickable {
    id: primaryScroll
    objectName: "agentsPrimaryScroll"
    width: parent.width
    visible: primaryColumn.implicitHeight > 0
    height: Math.min(primaryColumn.implicitHeight, Math.max(0, dropdown.bodyBudget - dropdown.detailReserve - (agentsScroll.visible ? dropdown.spacing : 0)))
    contentWidth: width
    contentHeight: primaryColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
    Column {
      id: primaryColumn
      width: primaryScroll.width
      spacing: Style.space(16)
      onImplicitHeightChanged: dropdown.noteLayoutChange()
      Rectangle {
        id: problemCard
        objectName: "problemCard"
        width: parent.width
        visible: String(dropdown.hero.problem || "") !== ""
        implicitHeight: problemText.implicitHeight + Style.space(16)
        radius: Aranea.DesignTokens.cornerRadius
        color: Util.alpha(Aranea.DesignTokens.urgent, 0.10)
        border.width: 1
        border.color: Util.alpha(Aranea.DesignTokens.urgent, 0.35)
        Text {
          id: problemText
          textFormat: Text.PlainText
          objectName: "problemText"
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          anchors.leftMargin: Style.space(12)
          anchors.rightMargin: Style.space(12)
          text: String(dropdown.hero.problem || "")
          wrapMode: Text.WordWrap
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.7)
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.caption
        }
      }
      Text {
        textFormat: Text.PlainText
        objectName: "emptyText"
        width: parent.width
        visible: !!dropdown.view.empty
        topPadding: Style.space(24)
        bottomPadding: Style.space(24)
        text: "No AI coding subscriptions found.\nAgents show up here once you've used them."
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.body
      }
      Rectangle {
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
        visible: balanceSection.visible
      }
      AgentsBalanceSection {
        id: balanceSection
        width: parent.width
        balance: dropdown.view.balance || null
      }
      Rectangle {
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
        visible: limitsSection.visible
      }
      AgentsLimitsSection {
        id: limitsSection
        width: parent.width
        rows: dropdown.view.limits || []
      }
    }
  }
  Flickable {
    id: agentsScroll
    objectName: "agentsScroll"
    width: parent.width
    // Whatever the pinned rows leave of maxHeight, never less than nothing,
    // so the dropdown never grows past maxHeight.
    visible: scrollColumn.implicitHeight > 0
    height: Math.max(0, Math.min(scrollColumn.implicitHeight, dropdown.bodyBudget - (primaryScroll.visible ? primaryScroll.height + dropdown.spacing : 0)))
    contentWidth: width
    contentHeight: scrollColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    onContentYChanged: dropdown.noteLayoutChange()
    onHeightChanged: {
      dropdown.noteLayoutChange()
      Qt.callLater(dropdown.ensureCursorVisible)
    }

    Column {
      id: scrollColumn
      width: agentsScroll.width
      spacing: Style.space(16)
      onImplicitHeightChanged: {
        dropdown.noteLayoutChange()
        Qt.callLater(dropdown.ensureCursorVisible)
      }

      Aranea.DisclosureSection {
        id: historyDisclosure
        objectName: "historyDisclosure"
        width: parent.width
        visible: (dropdown.view.days || []).length > 0
        title: "Usage history"
        expanded: !!(dropdown.view.details && dropdown.view.details.historyExpanded)
        keyboardFocused: dropdown.cursorIn("details") === 0
        pointerGate: dropdown.pointerGate
        onToggleRequested: dropdown.action("toggleDetails", {
          section: "history"
        })
        AgentsUsageSection {
          id: daysSection
          objectName: "daysSection"
          width: parent.width
          rows: dropdown.view.days || []
          pointerGate: dropdown.pointerGate
          onRowHovered: function (index) {
            dropdown.action("hover", {
              section: "days",
              index: index
            })
          }
        }
      }
      Aranea.DisclosureSection {
        id: modelsDisclosure
        objectName: "modelsDisclosure"
        width: parent.width
        visible: (dropdown.view.models || []).length > 0
        title: "Models"
        expanded: !!(dropdown.view.details && dropdown.view.details.modelsExpanded)
        keyboardFocused: dropdown.cursorIn("details") === 1
        pointerGate: dropdown.pointerGate
        onToggleRequested: dropdown.action("toggleDetails", {
          section: "models"
        })
        AgentsUsageSection {
          id: modelsSection
          objectName: "modelsSection"
          width: parent.width
          stacked: true
          rows: dropdown.view.models || []
          pointerGate: dropdown.pointerGate
          onRowHovered: function (index) {
            dropdown.action("hover", {
              section: "models",
              index: index
            })
          }
        }
      }
      Text {
        id: footerText
        textFormat: Text.PlainText
        objectName: "footerText"
        width: parent.width
        visible: text !== ""
        text: String(dropdown.view.footer || "")
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
  Text {
    id: keyHint
    textFormat: Text.PlainText
    objectName: "keyHint"
    width: parent.width
    // No hint, no line: an empty hint takes no height.
    visible: text !== ""
    text: String(dropdown.view.keyHint || "")
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The dropdown's last layout shift, for the pills' clickSettled().
    property real layoutChangedAt: dropdown.layoutChangedAt

    referenceItem: dropdown
  }
}
