// The Aranea Clock dropdown's YEAR and LIFE strands and the life edit row.
// Each strand is a caption with its percent on the right and a hairline
// lit accent to strandEnd up to that share. Stock's memento mori: a
// double-click on the year bar asks to edit the birth year and life
// expectancy, a double-click on the life bar asks to clear it. While
// editing, the BORN and LIVE TO fields show (seeded from bornText and
// liveToText, the born field focused with its text selected); Tab hops
// between them, Enter commits the pair and Esc cancels, as stock's
// handleLifeKey. Pure view: plain inputs in, signals out.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: life

  // The share of the year gone, in percent.
  property real yearPercent: 0
  // Whether the life bar shows (a birth year is set).
  property bool lifeVisible: false
  // The share of the life expectancy reached, in percent.
  property real lifePercent: 0
  // Whether the edit row shows.
  property bool editing: false
  // The born field's text when editing starts (or the host resets it).
  property string bornText: ""
  // The live-to field's text when editing starts (or the host resets it).
  property string liveToText: ""
  // The dropdown's PointerMoveGate, carrying layoutChangedAt.
  property var pointerGate: null

  // Emitted on a settled double-click: CLEAR is false on the year bar
  // (edit) and true on the life bar (clear).
  signal editLife(bool clear)
  // Emitted on Enter in either field with both fields' texts.
  signal commit(string born, string liveTo)
  // Emitted on Esc in either field.
  signal cancel
  // Emitted when a part shows or hides (the life bar, the edit row),
  // before the column has been laid out again.
  signal partShifted

  // Seeds both fields and focuses the born one with its text selected.
  function startEditing() {
    bornField.text = life.bornText
    liveToField.text = life.liveToText
    bornField.selectAll()
    bornField.forceActiveFocus()
  }

  // Stock's handleLifeKey: Esc cancels, Enter commits the pair, Tab and
  // Backtab hop to OTHER with its text selected.
  function handleKey(event, other) {
    if (event.key === Qt.Key_Escape) {
      life.cancel()
      event.accepted = true
    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
      life.commit(bornField.text, liveToField.text)
      event.accepted = true
    } else if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
      other.selectAll()
      other.forceActiveFocus()
      event.accepted = true
    }
  }

  spacing: Style.space(8)
  onEditingChanged: if (life.editing)
    Qt.callLater(life.startEditing)
  onBornTextChanged: bornField.text = life.bornText
  onLiveToTextChanged: liveToField.text = life.liveToText
  Component.onCompleted: if (life.editing)
    Qt.callLater(life.startEditing)

  // A caption with its percent on the right edge over a lit strand,
  // double-clickable through a settled target.
  component Strand: ClockTarget {
    id: strand
    // The caption, e.g. "YEAR".
    property string title: ""
    // The share lit, in percent.
    property real percent: 0
    // The percent text's objectName, for tests.
    property string percentName: ""
    // The strand's objectName, for tests.
    property string strandName: ""
    // Whether a double-click acts.
    property bool tappable: true
    // Hover tooltip; empty shows none.
    property string tooltipText: ""

    // Emitted on a settled double-click.
    signal doubleClicked

    implicitHeight: strandCaption.implicitHeight + Style.space(6) + strandTrack.height

    Text {
      id: strandCaption
      anchors.left: parent.left
      anchors.top: parent.top
      text: strand.title
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      objectName: strand.percentName
      anchors.right: parent.right
      anchors.verticalCenter: strandCaption.verticalCenter
      text: Math.round(strand.percent) + "%"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Rectangle {
      id: strandTrack
      // The share lit, 0..1.
      readonly property real fraction: Math.max(0, Math.min(1, strand.percent / 100))
      objectName: strand.strandName
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      height: Math.max(2, Style.space(2))
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.15)

      Rectangle {
        // The glow under the lit part.
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width * strandTrack.fraction
        height: Style.space(6)
        radius: height / 2
        color: Util.alpha(Aranea.DesignTokens.accent, 0.18)
      }
      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * strandTrack.fraction
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop {
            position: 0
            color: Aranea.DesignTokens.accent
          }
          GradientStop {
            position: 1
            color: Aranea.DesignTokens.strandEnd
          }
        }
      }
    }
    MouseArea {
      anchors.fill: parent
      enabled: strand.tappable
      onDoubleClicked: if (strand.clickSettled())
        strand.doubleClicked()
    }
    PanelToolTip {
      visible: strand.hot && strand.tooltipText !== ""
      text: strand.tooltipText
    }
  }

  Strand {
    objectName: "yearRow"
    width: life.width
    title: "YEAR"
    percent: life.yearPercent
    percentName: "yearPercent"
    strandName: "yearStrand"
    tappable: !life.editing
    pointerGate: life.pointerGate
    onDoubleClicked: life.editLife(false)
  }
  Strand {
    objectName: "lifeRow"
    width: life.width
    visible: life.lifeVisible
    title: "LIFE"
    percent: life.lifePercent
    percentName: "lifePercent"
    strandName: "lifeStrand"
    tooltipText: "Memento Mori"
    pointerGate: life.pointerGate
    onVisibleChanged: life.partShifted()
    onDoubleClicked: life.editLife(true)
  }
  Row {
    objectName: "lifeEdit"
    visible: life.editing
    spacing: Style.space(10)
    onVisibleChanged: life.partShifted()

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "BORN"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    TextField {
      id: bornField
      objectName: "bornField"
      width: Style.space(70)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "year"
      font.pixelSize: Style.font.caption
      inputMethodHints: Qt.ImhDigitsOnly
      Keys.onPressed: function (event) {
        life.handleKey(event, liveToField)
      }
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      leftPadding: Style.space(6)
      text: "LIVE TO"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    TextField {
      id: liveToField
      objectName: "liveToField"
      width: Style.space(60)
      anchors.verticalCenter: parent.verticalCenter
      placeholderText: "90"
      font.pixelSize: Style.font.caption
      inputMethodHints: Qt.ImhDigitsOnly
      Keys.onPressed: function (event) {
        life.handleKey(event, bornField)
      }
    }
  }
}
