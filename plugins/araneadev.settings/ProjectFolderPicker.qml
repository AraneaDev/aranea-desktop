// Desktop folder chooser with an always editable absolute-path alternative.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Commons
import "SettingsLogic.js" as Logic

ColumnLayout {
  id: picker
  // Explicitly disables chooser interaction for unavailable desktops and captures.
  property bool chooserAvailable: true
  // Inert captures do not open native dialogs or emit mutation requests.
  property bool displayOnly: false
  // Draft is presentation only; backend remains the canonical path validator.
  property string pathDraft: ''
  // Shared pointer/layout settling gate.
  property var pointerGate: null
  // Explain chooser errors while keeping the manual alternative accessible.
  property string error: ''
  // Context-specific chooser label, including explicit checkout relocation.
  property string buttonText: 'Choose folder'
  // The manual path alternative stays available even when a portal fails silently.
  readonly property bool fallbackVisible: true
  // Local absolute-path validation does not replace backend existence validation.
  readonly property bool validPath: Logic.normalizeFolder(pathDraft) !== ''
  // User confirmed a folder; consumers decide whether to add a root or relocate.
  signal folderRequested(string path)
  // Normalize local file URLs without interpreting folder text as commands.
  function setPath(value: string): void {
    pathDraft = Logic.normalizeFolder(value) || value
  }
  // Confirm the edited folder through the typed view boundary.
  function confirm(): void {
    if (!displayOnly && validPath)
      folderRequested(Logic.normalizeFolder(pathDraft))
  }
  // Invoke the native desktop chooser; the path field remains available on failure.
  function choose(): void {
    if (displayOnly)
      return
    if (!chooserAvailable) {
      error = 'Folder chooser unavailable. Enter an absolute folder path below.'
      return
    }
    try {
      dialog.open()
    } catch (e) {
      error = 'Folder chooser unavailable. Enter an absolute folder path below.'
    }
  }
  spacing: Style.space(8)
  SettingsButton {
    text: picker.buttonText
    enabled: !picker.displayOnly
    pointerGate: picker.pointerGate
    onClicked: picker.choose()
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: picker.error || 'Or enter an absolute folder path'
    opacity: 0.7
  }
  TextField {
    Layout.fillWidth: true
    text: picker.pathDraft
    placeholderText: '/home/you/Projects'
    enabled: !picker.displayOnly
    font.family: Style.font.family
    onTextEdited: picker.pathDraft = text
    onAccepted: picker.confirm()
    Accessible.name: 'Absolute project folder path'
  }
  SettingsButton {
    text: 'Use folder'
    enabled: !picker.displayOnly && picker.validPath
    pointerGate: picker.pointerGate
    onClicked: picker.confirm()
  }
  FolderDialog {
    id: dialog
    title: 'Choose a development folder'
    onAccepted: {
      picker.setPath(selectedFolder.toString())
      picker.confirm()
    }
  }
}
