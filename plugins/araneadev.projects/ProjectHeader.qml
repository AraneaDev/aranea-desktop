// Selected project identity and its primary action stay separate from settings.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: header
  objectName: 'projectHeader'
  // Current saved project identity; this view never changes registration.
  property var project: null
  // Observed workspace bindings supplied by the persistent owner.
  property var bindings: []
  // Whether the live owner can open workspace tools.
  property bool openAvailable: false
  // A project operation is pending; duplicate Open is disabled.
  property bool pending: false
  // Inert captures refuse workspace activation.
  property bool displayOnly: false
  // Shared pointer settling gate for content that moves during refresh.
  property var pointerGate: null
  // Resolve the saved selected checkout, falling back to its primary listing.
  readonly property var checkout: project ? (project.checkouts || []).filter(function (c) {
    return c.id === header.project.lastCheckoutId
  })[0] || (project.checkouts || [])[0] || null : null
  // Match only the observed workspace for the displayed project and checkout.
  readonly property var binding: project ? bindings.filter(function (b) {
    return b.projectId === header.project.id && (!header.checkout || b.checkoutId === header.checkout.id)
  })[0] || null : null
  // Request ordinary Open through the existing typed owner boundary.
  signal openRequested
  spacing: Style.space(8)
  GridLayout {
    Layout.fillWidth: true
    columns: header.width < Style.space(440) ? 1 : 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: header.project ? header.project.name : ''
      font.pixelSize: Style.font.heading
      font.bold: true
      maximumLineCount: header.width < Style.space(440) ? 3 : 2
      elide: Text.ElideRight
      ToolTip.visible: nameHover.hovered
      ToolTip.text: text
      HoverHandler {
        id: nameHover
      }
    }
    Aranea.ActionButton {
      objectName: 'projectPrimaryOpen'
      Layout.fillWidth: header.width < Style.space(440)
      text: header.pending ? 'Preparing…' : 'Open project'
      variant: 'primary'
      implicitHeight: Math.max(Style.space(34), Style.font.body + Style.space(16))
      enabled: !header.displayOnly && !header.pending && header.openAvailable
      pointerGate: header.pointerGate
      onClicked: header.openRequested()
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: header.checkout ? header.checkout.path : 'No registered checkout'
    technical: true
    opacity: 0.7
    wrapMode: Text.NoWrap
    elide: Text.ElideMiddle
    ToolTip.visible: pathHover.hovered
    ToolTip.text: text
    HoverHandler {
      id: pathHover
    }
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(12)
    Aranea.UiLabel {
      objectName: 'projectBranch'
      width: Math.min(implicitWidth, header.width)
      text: header.checkout ? 'Branch · ' + (header.checkout.branch || 'detached') : ''
      opacity: 0.8
    }
    Aranea.UiLabel {
      width: Math.min(implicitWidth, header.width)
      text: header.binding ? 'Workspace ' + header.binding.workspaceId : header.project && header.project.workspaceMode === 'current' ? 'Uses current workspace' : 'Dedicated workspace'
      opacity: 0.8
    }
    Aranea.UiLabel {
      width: Math.min(implicitWidth, header.width)
      text: header.openAvailable ? 'Ready to open' : 'Workspace opening unavailable'
      color: header.openAvailable ? Aranea.DesignTokens.accent : Aranea.DesignTokens.attention
    }
  }
}
