// Desktop folder chooser with an always editable absolute-path alternative.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "ProjectsLogic.js" as Logic
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: picker
  // Explicitly disables chooser interaction for unavailable desktops and captures.
  property bool chooserAvailable: true
  // Inert captures do not open dialogs or emit mutation requests.
  property bool displayOnly: false
  // Draft is presentation only; backend remains the canonical path validator.
  property string pathDraft: ''
  // An owning presentation model can retain drafts across checkout delegate recreation.
  property bool externalDraft: false
  // Shared pointer/layout settling gate.
  property var pointerGate: null
  // Explain chooser errors while keeping the manual alternative accessible.
  property string error: ''
  // A fresh dialog avoids Qt retaining a popup deleted with a hidden shell window.
  property var activeDialog: null
  // Release only the dialog that closed; queued cleanup cannot affect a newer one.
  function releaseDialog(expected = activeDialog): void {
    if (!expected || expected !== activeDialog)
      return
    activeDialog = null
    expected.close()
    expected.destroy()
  }
  // Context-specific chooser label, including explicit checkout relocation.
  property string buttonText: 'Choose folder'
  // The manual path alternative stays available independently of the dialog.
  readonly property bool fallbackVisible: true
  // Local absolute-path validation does not replace backend existence validation.
  readonly property bool validPath: Logic.normalizeFolder(pathDraft) !== ''
  // User confirmed a folder; consumers decide whether to add a root or relocate.
  signal folderRequested(string path)
  // Draft edits remain presentation only when a parent supplies the draft value.
  signal pathEdited(string path)
  // Keep externally supplied path bindings intact while typing or choosing a folder.
  function editPath(value: string): void {
    if (externalDraft)
      pathEdited(value)
    else
      pathDraft = value
  }
  // Normalize local file URLs without interpreting folder text as commands.
  function setPath(value: string): void {
    editPath(Logic.normalizeFolder(value) || value)
  }
  // Confirm the edited folder through the typed view boundary.
  function confirm(): void {
    if (!displayOnly && validPath)
      folderRequested(Logic.normalizeFolder(pathDraft))
  }
  // Invoke the Qt Quick chooser; the path field remains available on failure.
  function choose(): void {
    if (displayOnly)
      return
    if (!chooserAvailable) {
      error = 'Folder chooser unavailable. Enter an absolute folder path below.'
      return
    }
    try {
      if (activeDialog)
        return
      var overlay = picker.Controls.Overlay.overlay
      var previousItems = []
      if (overlay) {
        for (var i = 0; i < overlay.children.length; i++)
          previousItems.push(overlay.children[i])
      }
      activeDialog = folderDialogComponent.createObject(picker)
      activeDialog.open()
      // The public overlay contains the newly opened popup's Control font context.
      // Bind only that new item; Qt's GTK font cache can retain an older system size.
      if (overlay) {
        for (var j = 0; j < overlay.children.length; j++) {
          var item = overlay.children[j]
          if (previousItems.indexOf(item) < 0 && item.font !== undefined) {
            item.font = Qt.binding(function () {
              return Qt.font({
                family: Aranea.Typography.uiFamily,
                pixelSize: Style.font.body
              })
            })
          }
        }
      }
    } catch (e) {
      releaseDialog()
      error = 'Folder chooser unavailable. Enter an absolute folder path below.'
    }
  }
  // Shell windows are destroyed when hidden; close their chooser first.
  Connections {
    target: picker.Window.window
    function onVisibleChanged() {
      if (target && !target.visible)
        picker.releaseDialog()
    }
  }
  spacing: Style.space(8)
  Aranea.ActionButton {
    text: picker.buttonText
    enabled: !picker.displayOnly
    pointerGate: picker.pointerGate
    onClicked: picker.choose()
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: picker.error || 'Or enter an absolute folder path'
    opacity: 0.7
  }
  Ui.TextField {
    Layout.fillWidth: true
    text: picker.pathDraft
    placeholderText: '/home/you/Projects'
    enabled: !picker.displayOnly
    font.family: Style.font.family
    onTextEdited: picker.editPath(text)
    onAccepted: picker.confirm()
    Accessible.name: 'Absolute project folder path'
  }
  Aranea.ActionButton {
    text: 'Use folder'
    enabled: !picker.displayOnly && picker.validPath
    pointerGate: picker.pointerGate
    onClicked: picker.confirm()
  }
  Component {
    id: folderDialogComponent
    FolderDialog {
      id: dialog
      title: 'Choose a development folder'
      // GTK/GVFS native dialogs can segfault the shared Quickshell process.
      options: FolderDialog.DontUseNativeDialog
      // Projects is a layer-shell overlay; a separate window would tile beneath it.
      popupType: Controls.Popup.Item
      onVisibleChanged: if (!visible)
        Qt.callLater(function () {
          picker.releaseDialog(dialog)
        })
      onAccepted: {
        picker.setPath(selectedFolder.toString())
        picker.confirm()
      }
    }
  }
}
