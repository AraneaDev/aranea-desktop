// Problem list presentation for the health panel.
// qmllint disable missing-property unqualified
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: root
  // Public contract member.
  property var problems: []
  // Public contract member.
  property int cursor: -1
  // Public contract member.
  property color statusColor: Color.urgent
  // Public contract member.
  property color amber: Color.notifications.countdown
  // Public contract member.
  signal problemActivated(var problem)
  implicitHeight: content.implicitHeight

  ColumnLayout {
    id: content
    anchors.fill: parent
    spacing: Style.space(8)
    RowLayout {
      Layout.fillWidth: true
      Rectangle {
        Layout.preferredWidth: Style.space(3)
        Layout.preferredHeight: Style.font.body + Style.space(2)
        radius: width / 2
        color: root.statusColor
      }
      Text {
        text: "Problems"
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        Layout.fillWidth: true
      }
      Text {
        text: String(root.problems.length)
        color: Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }
    }
    Repeater {
      model: root.problems
      delegate: Item {
        required property var modelData
        required property int index
        Layout.fillWidth: true
        // The row is its text line; the cursor fill bleeds around it instead
        // of padding the row, so the text meets the panel's content edges and
        // the next section keeps the panel's section gap.
        implicitHeight: problemLine.implicitHeight

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -Style.space(8)
          anchors.rightMargin: -Style.space(8)
          anchors.topMargin: -Style.space(4)
          anchors.bottomMargin: -Style.space(4)
          radius: Aranea.DesignTokens.cornerRadius
          color: root.cursor === index ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
        }

        RowLayout {
          id: problemLine
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          Text {
            text: modelData.glyph
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }
          Text {
            text: modelData.summary
            color: Color.popups.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            Layout.fillWidth: true
            elide: Text.ElideRight
          }
          Text {
            text: modelData.urgency === 2 ? "critical" : "attention"
            color: modelData.urgency === 2 ? Color.urgent : root.amber
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          anchors.margins: -Style.space(4)
          onClicked: root.problemActivated(modelData)
        }
      }
    }
  }
}
