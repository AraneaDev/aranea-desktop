// Orientation-aware module section composition for the bar.
// qmllint disable missing-property unqualified
import QtQuick
import qs.Commons

Item {
  id: sections
  // Public contract member.
  property var leftModules: []
  // Public contract member.
  property var centerModules: []
  // Public contract member.
  property var rightModules: []
  // Public contract member.
  property bool vertical: false
  // Public contract member.
  property string position: "top"
  // Public contract member.
  property var widgetRegistry: ({})
  // Public contract member.
  signal moduleHovered(string moduleId, bool hovered)
  // Public contract member.
  signal modulePressed(string moduleId)

  implicitWidth: vertical ? Style.space(32) : left.implicitWidth + center.implicitWidth + right.implicitWidth
  implicitHeight: vertical ? left.implicitHeight + center.implicitHeight + right.implicitHeight : Style.space(32)

  Row {
    id: horizontal
    visible: !sections.vertical
    anchors.fill: parent
    Item {
      id: left
      implicitWidth: leftRow.implicitWidth
      implicitHeight: leftRow.implicitHeight
      Row {
        id: leftRow
        Repeater {
          model: sections.leftModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: false
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
    Item {
      id: center
      implicitWidth: centerRow.implicitWidth
      implicitHeight: centerRow.implicitHeight
      anchors.horizontalCenter: parent.horizontalCenter
      Row {
        id: centerRow
        Repeater {
          model: sections.centerModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: false
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
    Item {
      id: right
      implicitWidth: rightRow.implicitWidth
      implicitHeight: rightRow.implicitHeight
      anchors.right: parent.right
      Row {
        id: rightRow
        Repeater {
          model: sections.rightModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: false
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
  }

  Column {
    visible: sections.vertical
    anchors.fill: parent
    Item {
      implicitWidth: leftColumn.implicitWidth
      implicitHeight: leftColumn.implicitHeight
      Column {
        id: leftColumn
        Repeater {
          model: sections.leftModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: true
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
    Item {
      implicitWidth: centerColumn.implicitWidth
      implicitHeight: centerColumn.implicitHeight
      anchors.horizontalCenter: parent.horizontalCenter
      Column {
        id: centerColumn
        Repeater {
          model: sections.centerModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: true
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
    Item {
      implicitWidth: rightColumn.implicitWidth
      implicitHeight: rightColumn.implicitHeight
      anchors.bottom: parent.bottom
      Column {
        id: rightColumn
        Repeater {
          model: sections.rightModules
          delegate: BarModuleSlot {
            moduleId: modelData
            vertical: true
            onHoverChanged: sections.moduleHovered(moduleId, hovered)
            onPressed: sections.modulePressed(moduleId)
          }
        }
      }
    }
  }
}
