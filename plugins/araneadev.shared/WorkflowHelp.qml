// Selectable, offline help shared by project setup and agent surfaces.
// Host font tokens are dynamic QObject properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "WorkflowHelp.js" as Help

Column {
  id: guide
  // Hosts choose one fixed workflow and own scrolling and visibility.
  property string topic: 'agents'
  // Contextual heading supplied by the hosting surface.
  property string title: topic === 'projects' ? 'Projects help' : topic === 'actions' ? 'Workflow actions help' : 'Agents help'
  spacing: Style.space(16)
  Text {
    width: parent.width
    text: guide.title
    textFormat: Text.PlainText
    wrapMode: Text.Wrap
    color: DesignTokens.foreground
    font.family: Typography.uiFamily
    font.pixelSize: Style.font.title
    font.bold: true
  }
  Repeater {
    model: Help.sections(guide.topic)
    Column {
      required property var modelData
      width: guide.width
      spacing: Style.space(6)
      Text {
        width: parent.width
        text: parent.modelData.title
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        color: DesignTokens.accent
        font.family: Typography.uiFamily
        font.pixelSize: Style.font.body
        font.bold: true
      }
      TextEdit {
        width: parent.width
        text: parent.modelData.body
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.Wrap
        color: DesignTokens.foreground
        font.family: Typography.uiFamily
        font.pixelSize: Style.font.body
      }
      TextEdit {
        width: parent.width
        text: parent.modelData.command || ''
        visible: text !== ''
        readOnly: true
        selectByMouse: true
        textFormat: TextEdit.PlainText
        wrapMode: TextEdit.WrapAnywhere
        color: DesignTokens.foreground
        font.family: Typography.technicalFamily
        font.pixelSize: Style.font.body
      }
    }
  }
}
