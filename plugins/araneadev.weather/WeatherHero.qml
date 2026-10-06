// The Aranea Weather dropdown's hero: the condition glyph, the big
// temperature over the condition label, and on the right content edge the
// place (click to edit, pulsing while a new place saves) or, while
// editing, the place edit, over the updated label (click to refresh).
// Under it, the RAIN SOON line (hidden when empty) and a travelling
// strand while the forecast loads. Pure view: plain inputs in, signals
// out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: hero

  // The view's hero part: {glyph, temp, label, place, updated, loading}.
  property var heroView: ({})
  // The rain soon line, or "" to hide it.
  property string rainSoon: ""
  // Whether the place edit is open.
  property bool editing: false
  // Whether a new place is being saved: the place label pulses.
  property bool saving: false
  // The place edit's text when editing starts.
  property string editText: ""
  // The keyboard cursor's section when active ("place", "refresh",
  // "clear"), or "".
  property string cursorSection: ""
  // The dropdown's PointerMoveGate, carrying layoutChangedAt.
  property var pointerGate: null

  // Emitted on a settled click on the place label (never while saving).
  signal editPlace
  // Emitted on a settled click on the updated label.
  signal refresh
  // Emitted when typing changes the place field to TEXT.
  signal query(string text)
  // Emitted on Enter in the place field with its TEXT.
  signal commit(string text)
  // Emitted on Esc in the place field.
  signal cancel
  // Emitted on Up (-1) or Down (+1) in the place field.
  signal step(int delta)
  // Emitted on a settled click on the clear button.
  signal clearPlace
  // Emitted when the pointer really moves onto the control in SECTION
  // ("place", "refresh", "clear").
  signal hovered(string section)
  // Emitted when a part shows or hides (rain soon, the loading strand, the
  // updated label),
  // before the column has been laid out again.
  signal partShifted

  spacing: Style.space(6)

  Item {
    id: top
    width: hero.width
    implicitHeight: Math.max(left.implicitHeight, right.implicitHeight)

    Row {
      id: left
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(14)

      Text {
        objectName: "heroGlyph"
        anchors.verticalCenter: parent.verticalCenter
        text: hero.heroView.glyph || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
        font.family: Aranea.Typography.iconFamily
        font.pixelSize: Style.font.displayLarge
      }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)

        Text {
          objectName: "heroTemp"
          textFormat: Text.PlainText
          text: hero.heroView.temp || ""
          color: Aranea.DesignTokens.foreground
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Math.round(Style.font.displayLarge * 1.4)
          font.bold: true
        }
        Text {
          objectName: "heroLabel"
          textFormat: Text.PlainText
          text: String(hero.heroView.label || "")
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.6
        }
      }
    }
    Column {
      id: right
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(4)

      WeatherLink {
        objectName: "placeLabel"
        anchors.right: parent.right
        visible: !hero.editing
        text: String(hero.heroView.place || "")
        glyph: String.fromCodePoint(0xf03eb)
        restColor: Aranea.DesignTokens.foreground
        pixelSize: Style.font.subtitle
        bold: true
        letterSpacing: 0
        tooltipText: "Edit place"
        busy: hero.saving
        hasCursor: hero.cursorSection === "place"
        pointerGate: hero.pointerGate
        onClicked: if (!hero.saving)
          hero.editPlace()
        onHoveredMoved: hero.hovered("place")
      }
      WeatherPlaceEdit {
        objectName: "placeEdit"
        anchors.right: parent.right
        visible: hero.editing
        active: hero.editing
        editText: hero.editText
        saving: hero.saving
        clearCursor: hero.cursorSection === "clear"
        pointerGate: hero.pointerGate
        onQuery: function (text) {
          hero.query(text)
        }
        onCommit: function (text) {
          hero.commit(text)
        }
        onCancel: hero.cancel()
        onStep: function (delta) {
          hero.step(delta)
        }
        onClear: hero.clearPlace()
        onClearHovered: hero.hovered("clear")
      }
      WeatherLink {
        objectName: "updatedLabel"
        anchors.right: parent.right
        visible: text !== ""
        text: hero.heroView.updated || ""
        pixelSize: Style.font.bodySmall
        tooltipText: "Refresh"
        hasCursor: hero.cursorSection === "refresh"
        // Showing or hiding moves the place label above it (the column is
        // centred in the row): stamp the layout.
        onVisibleChanged: hero.partShifted()
        pointerGate: hero.pointerGate
        onClicked: hero.refresh()
        onHoveredMoved: hero.hovered("refresh")
      }
    }
  }
  Item {
    objectName: "rainSoonRow"
    width: hero.width
    visible: hero.rainSoon !== ""
    implicitHeight: Math.max(rainCaption.implicitHeight, rainText.implicitHeight)
    onVisibleChanged: hero.partShifted()

    Text {
      id: rainCaption
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "RAIN SOON"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
    }
    Text {
      id: rainText
      objectName: "rainSoonText"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: hero.rainSoon
      color: Aranea.DesignTokens.foreground
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.bodySmall
    }
  }
  Aranea.FilamentPulse {
    objectName: "loadingPulse"
    width: hero.width
    running: !!hero.heroView.loading
    onVisibleChanged: hero.partShifted()
  }
}
