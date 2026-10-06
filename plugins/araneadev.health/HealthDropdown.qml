// Health panel composition. The plugin host owns lifecycle, expansion and keys.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "HealthLogic.js" as HealthLogic

Item {
  id: root
  // Whether a health service with metrics is published.
  property bool available: false
  // Existing health severity from the service.
  property string status: "healthy"
  // All actionable problems in service order.
  property var problems: []
  // The service metrics, or null while unavailable.
  property var metrics: null
  // Whether the owning dropdown is open.
  property bool active: false
  // Host-owned key of the current keyboard target.
  property string cursorKey: ""
  // Whether the keyboard outline is currently shown.
  property bool keyboardCursor: false
  // Host-owned Resource details expansion state.
  property bool resourcesExpanded: false
  // Host-owned Processes expansion state.
  property bool processesExpanded: false
  // Attention foreground token.
  readonly property color amber: Aranea.DesignTokens.attention
  // Availability-aware identity glyph foreground.
  readonly property color statusColor: !available ? Util.alpha(Aranea.DesignTokens.foreground, 0.55) : status === "critical" ? Aranea.DesignTokens.urgent : status === "attention" ? root.amber : Aranea.DesignTokens.ceremony
  // Reports a settled, keyed problem activation.
  signal problemActivated(int index, string key)
  // Requests a host-owned Resource details toggle.
  signal resourcesToggleRequested
  // Requests a host-owned Processes toggle.
  signal processesToggleRequested
  implicitHeight: content.implicitHeight
  width: Style.space(380)
  height: implicitHeight
  // Host-owned content budget excludes the popup's padding and borders.
  property real maxContentHeight: Infinity
  // Fixed identity, decision and hint budget, including section spacing.
  readonly property real fixedContentHeight: header.implicitHeight + decision.implicitHeight + keyHint.implicitHeight + Style.space(16) * 3
  // Height left for problems, compact resources and optional details.
  readonly property real maxScrollHeight: Math.max(0, root.maxContentHeight - root.fixedContentHeight)
  // The capped body viewport, used by the host to reset scroll on close.
  readonly property alias scrollViewport: bodyScroll
  // The keyed problem rows and shared pointer settling gate.
  readonly property alias problemsView: problemsSection
  // The resource disclosure and its heading target.
  readonly property alias resourcesDisclosure: resourcesDetails
  // The process disclosure and its heading target.
  readonly property alias processesDisclosure: processesDetails

  // Stamps shifted content for both problem rows and disclosure headings.
  function noteLayoutChange() {
    problemsSection.noteLayoutChange()
  }
  // Clears stale pointer samples before keyboard navigation.
  function disarmPointer() {
    problemsSection.disarmPointer()
  }
  // The height of a disclosure heading, excluding its expanded content.
  function headingHeight(section) {
    for (var i = 0; i < section.children.length; i++)
      if (section.children[i].objectName === "disclosureHeading")
        return section.children[i].height
    return 0
  }
  // Keep keyed targets reachable when problem lists or details overflow.
  function ensureCursorVisible(): void {
    if (!root.keyboardCursor)
      return
    var target = root.cursorKey === "details:resources" ? resourcesDetails : root.cursorKey === "details:processes" ? processesDetails : problemsSection.rowAt(HealthLogic.indexOfKey(root.problems, root.cursorKey))
    if (!target)
      return
    var top = target.mapToItem(bodyContent, 0, 0).y
    var targetHeight = root.cursorKey.indexOf("details:") === 0 ? root.headingHeight(target) : target.height
    var maxY = Math.max(0, bodyScroll.contentHeight - bodyScroll.height)
    if (top < bodyScroll.contentY)
      bodyScroll.contentY = Math.max(0, top)
    else if (top + targetHeight > bodyScroll.contentY + bodyScroll.height)
      bodyScroll.contentY = Math.min(maxY, top + targetHeight - bodyScroll.height)
  }
  onCursorKeyChanged: Qt.callLater(root.ensureCursorVisible)
  onKeyboardCursorChanged: Qt.callLater(root.ensureCursorVisible)

  onResourcesExpandedChanged: {
    root.noteLayoutChange()
    Qt.callLater(root.ensureCursorVisible)
  }
  onProcessesExpandedChanged: {
    root.noteLayoutChange()
    Qt.callLater(root.ensureCursorVisible)
  }
  ColumnLayout {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: Style.space(16)
    onImplicitHeightChanged: problemsSection.noteLayoutChange()

    Aranea.DropdownHeader {
      id: header
      Layout.fillWidth: true
      glyph: String.fromCodePoint(0xf05f6)
      glyphColor: root.statusColor
      title: root.metrics && root.metrics.hostname ? root.metrics.hostname : "Health"
      caption: root.metrics && root.metrics.uptime ? root.metrics.uptime : ""
    }

    HealthSummary {
      id: decision
      Layout.fillWidth: true
      available: root.available
      status: root.status
      problems: root.problems
      showResources: false
    }

    Flickable {
      id: bodyScroll
      objectName: "healthScroll"
      Layout.fillWidth: true
      Layout.preferredHeight: Math.min(bodyContent.implicitHeight, root.maxScrollHeight)
      contentWidth: width
      contentHeight: bodyContent.implicitHeight
      clip: true
      interactive: contentHeight > height
      boundsBehavior: Flickable.StopAtBounds
      onContentYChanged: problemsSection.noteLayoutChange()
      onHeightChanged: {
        problemsSection.noteLayoutChange()
        Qt.callLater(root.ensureCursorVisible)
      }

      ColumnLayout {
        id: bodyContent
        width: bodyScroll.width
        spacing: Style.space(16)
        onImplicitHeightChanged: {
          problemsSection.noteLayoutChange()
          Qt.callLater(root.ensureCursorVisible)
        }

        HealthProblemsSection {
          id: problemsSection
          visible: root.problems.length > 0
          Layout.fillWidth: true
          problems: root.problems
          hostContentHeight: content.implicitHeight
          cursor: HealthLogic.outlineIndex(root.problems, root.cursorKey, root.keyboardCursor)
          amber: root.amber
          onProblemActivated: function (index, key) {
            root.problemActivated(index, key)
          }
        }

        HealthSummary {
          Layout.fillWidth: true
          available: root.available
          metrics: root.metrics
          showHealth: false
        }

        Aranea.DisclosureSection {
          id: resourcesDetails
          Layout.fillWidth: true
          title: "Resource details"
          expanded: root.resourcesExpanded
          keyboardFocused: root.keyboardCursor && root.cursorKey === "details:resources"
          pointerGate: problemsSection.pointerGate
          onToggleRequested: {
            root.resourcesToggleRequested()
          }
          HealthResourceSection {
            width: parent.width
            metrics: root.metrics
            active: root.active && root.resourcesExpanded
          }
        }

        Aranea.DisclosureSection {
          id: processesDetails
          Layout.fillWidth: true
          title: "Processes"
          expanded: root.processesExpanded
          keyboardFocused: root.keyboardCursor && root.cursorKey === "details:processes"
          pointerGate: problemsSection.pointerGate
          onToggleRequested: {
            root.processesToggleRequested()
          }
          HealthProcessSection {
            width: parent.width
            cpuProcesses: root.metrics && root.metrics.topProcs ? root.metrics.topProcs.cpu : []
            memoryProcesses: root.metrics && root.metrics.topProcs ? root.metrics.topProcs.mem : []
          }
        }
      }
    }

    Text {
      id: keyHint
      objectName: "keyHint"
      Layout.fillWidth: true
      text: "↑↓ move · enter open / expand"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      // qmllint disable missing-property
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      // qmllint enable missing-property
      elide: Text.ElideRight
    }
  }
}
