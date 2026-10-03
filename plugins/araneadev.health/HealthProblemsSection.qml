// The problem list in the health dropdown: a "PROBLEMS · n" caption, then
// one Aranea.NodeDeviceRow per open problem (its node and detail tinted
// urgent for a critical problem, amber otherwise), or the "All systems
// healthy" line when there are none. Pure view: rows in, keyed signals out.
//
// Every row is keyed by HealthLogic.problemKey (the problem's id, else its
// text) and an action is refused when the row no longer carries the key it
// was aimed at. The Repeater runs over the row count, so the service
// handing over a fresh problems array every check never recreates a row
// under a resting pointer. When the rows really move (the joined keys
// change) the section stamps layoutChangedAt, which the rows read through
// pointerGate: a click within 300 ms of it is ignored unless the pointer
// has really moved onto the row since. The mint outline is drawn only on
// cursor, which the host sets only while the keyboard drives it; pointer
// hover never highlights a row.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "HealthLogic.js" as HealthLogic

Column {
  id: section

  // Annotated problem rows ({key, summary, glyph, urgency, ...}), most
  // urgent first.
  property var problems: []
  // Row index of the keyboard cursor, -1 for none (the host passes -1
  // while the pointer drives, so the outline is keyboard only).
  property int cursor: -1
  // Colour of an attention (non-critical) problem's node and detail.
  property color amber: Aranea.DesignTokens.attention
  // When the rows last moved under the pointer (Date.now()), 0 for never.
  property real layoutChangedAt: 0
  // The rows' keys joined, so an equal list rebuilt does not stamp.
  readonly property string rowKeys: HealthLogic.problemKeys(section.problems)
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the rows' clickSettled().
  readonly property alias pointerGate: gate

  // Emitted when row INDEX, still holding KEY, is clicked (settled).
  signal problemActivated(int index, string key)
  // Emitted when the pointer really moves onto row INDEX.
  signal rowHovered(int index)

  // Stamps layoutChangedAt: the rows moved without the pointer moving.
  function noteLayoutChange() {
    section.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every key so a stale pointer
  // sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // Reports row INDEX as activated, refused when it no longer holds KEY.
  function activateRow(index, key) {
    if (HealthLogic.keyedProblem(section.problems, index, key))
      section.problemActivated(index, key)
  }

  // The row at INDEX (objectName "problemRow"), or null.
  function rowAt(index) {
    return repeater.itemAt(index)
  }

  spacing: Style.space(4)
  onRowKeysChanged: section.noteLayoutChange()

  Text {
    objectName: "problemsCaption"
    width: parent.width
    text: "PROBLEMS · " + section.problems.length
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  Row {
    objectName: "healthyLine"
    visible: section.problems.length === 0
    spacing: Style.space(8)
    Image {
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(16)
      height: Style.space(16)
      source: Aranea.RuntimePaths.glyphUrl
      sourceSize: Qt.size(32, 32)
    }
    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: "All systems healthy"
      color: Aranea.DesignTokens.ceremony
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }

  // The model is the row count, not the array: see the header.
  Repeater {
    id: repeater
    model: section.problems.length
    Aranea.NodeDeviceRow {
      id: row
      required property int index
      // This row's problem, read from the live array.
      readonly property var problem: section.problems[row.index] || ({})
      // The row's key, sent with its action.
      readonly property string key: HealthLogic.problemKey(row.problem)
      // Whether the problem is critical.
      readonly property bool critical: row.problem.urgency === 2

      objectName: "problemRow"
      width: section.width
      glyph: row.problem.glyph || ""
      label: row.problem.summary || ""
      detail: row.critical ? "critical" : "attention"
      detailColor: row.critical ? Aranea.DesignTokens.urgent : section.amber
      nodeColor: row.critical ? Aranea.DesignTokens.urgent : section.amber
      active: true
      hasCursor: section.cursor === row.index
      pointerGate: section.pointerGate
      onChosen: section.activateRow(row.index, row.key)
      onEntered: section.rowHovered(row.index)
    }
  }

  PointerMoveGate {
    id: gate
    // The section's last layout shift, for the rows' clickSettled().
    property real layoutChangedAt: section.layoutChangedAt

    referenceItem: section
  }
}
