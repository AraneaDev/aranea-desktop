// Header of the Aranea Network dropdown: the shared DropdownHeader with
// stock's hero actions in its trailing slot (QR share, speed test, the
// Wi-Fi switch, each only when it applies) and a full-width scan pulse
// under it. Pure view: plain inputs in, signals out.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: header

  // Connection glyph (a Nerd Font icon).
  property string glyph: ""
  // Title, e.g. "Interwebz24Ghz (2.4 GHz)".
  property string title: ""
  // Caption under the title (the rotating phrase or "Not connected").
  property string caption: ""
  // Opacity of the caption alone, for the phrase fade.
  property real captionOpacity: 1
  // Whether the QR share action applies (a connected non-enterprise Wi-Fi).
  property bool canQr: false
  // Whether the speed test action applies (there is an interface).
  property bool canSpeed: false
  // Whether the Wi-Fi switch applies (NetworkManager and a Wi-Fi station).
  property bool canToggle: false
  // Whether the Wi-Fi radio is on.
  property bool wifiOn: false
  // The switch's tooltip, e.g. "Turn Wi-Fi off".
  property string toggleHint: ""
  // Whether a Wi-Fi scan is running: lights the pulse.
  property bool scanning: false
  // The keyboard cursor's action among the visible ones, in stock order
  // QR, speed, switch; -1 when the cursor isn't on the header.
  property int cursorIndex: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from an
  // action moving under a still pointer.
  property var pointerGate: null
  // QR's index among the visible actions, or -1 when hidden (stock's).
  readonly property int qrIndex: canQr ? 0 : -1
  // Speed's index among the visible actions, or -1 when hidden.
  readonly property int speedIndex: canSpeed ? (canQr ? 1 : 0) : -1
  // The switch's index among the visible actions, or -1 when hidden.
  readonly property int toggleIndex: canToggle ? (canQr ? 1 : 0) + (canSpeed ? 1 : 0) : -1

  // Emitted when the QR action is clicked.
  signal qr
  // Emitted when the speed test action is clicked.
  signal speed
  // Emitted when the Wi-Fi switch is toggled.
  signal toggleWifi
  // Emitted when the pointer moves onto the action at INDEX (visible order).
  signal hoverAction(int index)

  // Reports a gated pointer move over HANDLER's item as hoverAction(INDEX);
  // without a gate, entering it reports instead (see the handlers below).
  function pointerOver(handler, index) {
    if (header.pointerGate && handler.hovered && header.pointerGate.moved(handler.parent, {
      x: handler.point.position.x,
      y: handler.point.position.y
    }))
      header.hoverAction(index)
  }

  objectName: "networkHeader"
  spacing: Style.space(6)

  // A glyph button in the header's trailing row, with the cursor outline.
  component GlyphAction: Item {
    id: action
    // The Nerd Font glyph.
    property string glyph: ""
    // Whether the keyboard cursor is on it.
    property bool hasCursor: false
    // Whether the pointer is over it.
    readonly property alias hovered: actionHover.hovered
    // Emitted on a click.
    signal clicked
    // Emitted when the pointer enters it.
    signal pointerEntered
    // Emitted when the pointer moves over it, HANDLER being its HoverHandler.
    signal pointerMoved(var handler)
    implicitWidth: glyphText.implicitWidth + Style.space(10)
    implicitHeight: glyphText.implicitHeight + Style.space(4)
    Aranea.HoverTint {}
    Rectangle {
      // The keyboard cursor outline.
      objectName: "cursorOutline"
      anchors.fill: parent
      color: action.hasCursor ? Util.alpha(Aranea.DesignTokens.accent, 0.08) : "transparent"
      border.width: action.hasCursor ? 1 : 0
      border.color: Aranea.DesignTokens.accent
    }
    Text {
      id: glyphText
      anchors.centerIn: parent
      text: action.glyph
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: action.clicked()
    }
    HoverHandler {
      id: actionHover
      onHoveredChanged: if (hovered)
        action.pointerEntered()
      onPointChanged: action.pointerMoved(actionHover)
    }
  }

  Aranea.DropdownHeader {
    width: parent.width
    glyph: header.glyph
    title: header.title
    caption: header.caption
    captionOpacity: header.captionOpacity

    Row {
      spacing: Style.space(8)

      GlyphAction {
        id: qrAction
        objectName: "qrAction"
        anchors.verticalCenter: parent.verticalCenter
        visible: header.canQr
        glyph: String.fromCodePoint(0xf0432)
        hasCursor: header.cursorIndex >= 0 && header.cursorIndex === header.qrIndex
        onClicked: header.qr()
        onPointerMoved: function (handler) {
          header.pointerOver(handler, header.qrIndex)
        }
        onPointerEntered: if (!header.pointerGate)
          header.hoverAction(header.qrIndex)
        PanelToolTip {
          objectName: "qrTip"
          visible: qrAction.hovered
          text: "Show QR code"
        }
      }
      GlyphAction {
        id: speedAction
        objectName: "speedAction"
        anchors.verticalCenter: parent.verticalCenter
        visible: header.canSpeed
        glyph: String.fromCodePoint(0xf04c5)
        hasCursor: header.cursorIndex >= 0 && header.cursorIndex === header.speedIndex
        onClicked: header.speed()
        onPointerMoved: function (handler) {
          header.pointerOver(handler, header.speedIndex)
        }
        onPointerEntered: if (!header.pointerGate)
          header.hoverAction(header.speedIndex)
        PanelToolTip {
          objectName: "speedTip"
          visible: speedAction.hovered
          text: "Run a speed test"
        }
      }
      Aranea.FilamentSwitch {
        id: wifiSwitch
        objectName: "wifiSwitch"
        anchors.verticalCenter: parent.verticalCenter
        visible: header.canToggle
        checked: header.wifiOn
        hasCursor: header.cursorIndex >= 0 && header.cursorIndex === header.toggleIndex
        onToggled: header.toggleWifi()
        HoverHandler {
          id: switchHover
          onPointChanged: header.pointerOver(switchHover, header.toggleIndex)
          onHoveredChanged: if (hovered && !header.pointerGate)
            header.hoverAction(header.toggleIndex)
        }
        PanelToolTip {
          objectName: "toggleTip"
          visible: switchHover.hovered && header.toggleHint !== ""
          text: header.toggleHint
        }
      }
    }
  }
  Aranea.FilamentPulse {
    objectName: "scanPulse"
    width: parent.width
    running: header.scanning
  }
}
