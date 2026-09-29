// Orientation-aware module section composition for the bar.
import QtQuick
import qs.Commons

Item {
  id: sections
  property var leftModules: []
  property var centerModules: []
  property var rightModules: []
  property bool vertical: false
  property string position: "top"
  property var widgetRegistry: ({})
  signal moduleHovered(string moduleId, bool hovered)
  signal modulePressed(string moduleId)

  implicitWidth: vertical ? Style.space(32) : left.implicitWidth + center.implicitWidth + right.implicitWidth
  implicitHeight: vertical ? left.implicitHeight + center.implicitHeight + right.implicitHeight : Style.space(32)

  Row {
    id: horizontal
    visible: !sections.vertical
    anchors.fill: parent
    Item { id: left; implicitWidth: leftRow.implicitWidth; implicitHeight: leftRow.implicitHeight; Row { id: leftRow; Repeater { model: sections.leftModules; delegate: BarModuleSlot { moduleId: modelData; vertical: false; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
    Item { id: center; implicitWidth: centerRow.implicitWidth; implicitHeight: centerRow.implicitHeight; anchors.horizontalCenter: parent.horizontalCenter; Row { id: centerRow; Repeater { model: sections.centerModules; delegate: BarModuleSlot { moduleId: modelData; vertical: false; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
    Item { id: right; implicitWidth: rightRow.implicitWidth; implicitHeight: rightRow.implicitHeight; anchors.right: parent.right; Row { id: rightRow; Repeater { model: sections.rightModules; delegate: BarModuleSlot { moduleId: modelData; vertical: false; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
  }

  Column {
    visible: sections.vertical
    anchors.fill: parent
    Item { implicitWidth: leftColumn.implicitWidth; implicitHeight: leftColumn.implicitHeight; Column { id: leftColumn; Repeater { model: sections.leftModules; delegate: BarModuleSlot { moduleId: modelData; vertical: true; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
    Item { implicitWidth: centerColumn.implicitWidth; implicitHeight: centerColumn.implicitHeight; anchors.horizontalCenter: parent.horizontalCenter; Column { id: centerColumn; Repeater { model: sections.centerModules; delegate: BarModuleSlot { moduleId: modelData; vertical: true; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
    Item { implicitWidth: rightColumn.implicitWidth; implicitHeight: rightColumn.implicitHeight; anchors.bottom: parent.bottom; Column { id: rightColumn; Repeater { model: sections.rightModules; delegate: BarModuleSlot { moduleId: modelData; vertical: true; onHoverChanged: sections.moduleHovered(moduleId, hovered); onPressed: sections.modulePressed(moduleId) } } } }
  }
}
