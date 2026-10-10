// Folder selection stays inside Qt Quick and emits only on explicit acceptance.
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Observe the public selection boundary without a registry or desktop command.
  property var requests: []
  QmlTest {
    id: t
  }
  FloatingWindow {
    visible: true
    implicitWidth: 500
    implicitHeight: 300
    Settings.ProjectFolderPicker {
      id: picker
      width: 480
      onFolderRequested: function (path) {
        host.requests = host.requests.concat([path])
      }
    }
  }
  Component.onCompleted: t.step(100, function () {
    var dialog = null
    for (var i = 0; i < picker.data.length; i++) {
      if (picker.data[i].selectedFolder !== undefined)
        dialog = picker.data[i]
    }
    t.check(dialog !== null, 'production picker owns its folder dialog')
    if (!dialog) {
      t.done()
      return
    }
    var safe = !!(dialog.options & FolderDialog.DontUseNativeDialog)
    t.check(safe, 'folder chooser bypasses in-process native GTK/GVFS')
    // Refuse to open the crashing native path when the regression is present.
    if (!safe) {
      t.done()
      return
    }
    t.equal(dialog.popupType, Controls.Popup.Item, 'chooser stays inside Settings instead of creating a tiled window')
    if (dialog.popupType !== Controls.Popup.Item) {
      t.done()
      return
    }
    picker.displayOnly = true
    picker.choose()
    t.check(!dialog.visible, 'inert picker cannot open a folder dialog')
    picker.displayOnly = false
    dialog.currentFolder = 'file:///tmp'
    picker.choose()
    t.waitFor(function () {
      return dialog.visible
    }, 3000, 'Qt Quick folder chooser opens', function () {
      t.equal(host.requests, [], 'opening chooser does not submit a folder')
      dialog.reject()
      t.equal(host.requests, [], 'cancelling chooser does not submit a folder')
      picker.choose()
      t.waitFor(function () {
        return dialog.visible
      }, 3000, 'folder chooser reopens after cancellation', function () {
        dialog.selectedFolder = 'file:///tmp'
        dialog.accept()
        t.equal(picker.pathDraft, '/tmp', 'accepted folder updates the editable absolute path')
        t.equal(host.requests, ['/tmp'], 'acceptance submits exactly one normalized folder')
        t.done()
      })
    })
  })
}
