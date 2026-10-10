// Folder selection stays inside Qt Quick and emits only on explicit acceptance.
import QtQuick
import QtQuick.Controls as Controls
import QtQuick.Dialogs
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.settings" as Settings
import "plugins/araneadev.shared" as Shared

ShellRoot {
  id: host
  // Observe the public selection boundary without a registry or desktop command.
  property var requests: []
  QmlTest {
    id: t
  }
  FloatingWindow {
    id: window
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
    picker.displayOnly = true
    picker.choose()
    t.check(picker.activeDialog === null, 'inert picker cannot create a folder dialog')
    picker.displayOnly = false
    picker.choose()
    var dialog = picker.activeDialog
    t.check(dialog !== null, 'production picker creates its folder dialog')
    if (!dialog) {
      t.done()
      return
    }
    t.check(!!(dialog.options & FolderDialog.DontUseNativeDialog), 'folder chooser bypasses in-process native GTK/GVFS')
    t.equal(dialog.popupType, Controls.Popup.Item, 'chooser stays inside Settings instead of creating a tiled window')
    t.waitFor(function () {
      return dialog.visible
    }, 3000, 'Qt Quick folder chooser opens', function () {
      var popup = picker.Controls.Overlay.overlay.children.filter(function (child) {
        return child.visible && child.font !== undefined
      })[0]
      t.check(!!popup, 'chooser exposes its visual font context inside the overlay')
      if (popup) {
        t.equal(popup.font.pixelSize, Style.font.body, 'chooser uses shared logical body size rather than a cached Qt font')
        t.equal(popup.font.family, Shared.Typography.uiFamily, 'chooser uses shared interface family')
        Style.fontBaseSize = 16
        Shared.Typography.preferences = ({
            uiFamily: 'Source Sans 3',
            technicalFamily: ''
          })
        t.equal(popup.font.pixelSize, Style.font.body, 'open chooser follows a live shared size change')
        t.equal(popup.font.family, 'Source Sans 3', 'open chooser follows a live interface family change')
        Style.fontBaseSize = 12
        Shared.Typography.preferences = ({})
      }
      t.equal(host.requests, [], 'opening chooser does not submit a folder')
      dialog.reject()
      t.equal(host.requests, [], 'cancelling chooser does not submit a folder')
      window.visible = false
      t.step(100, function () {
        window.visible = true
        t.step(100, function () {
          t.check(picker.activeDialog === null, 'closed dialog is released before shell window recreation')
          picker.choose()
          dialog = picker.activeDialog
          t.waitFor(function () {
            return dialog.visible
          }, 3000, 'folder chooser reopens after cancellation', function () {
            dialog.selectedFolder = 'file:///tmp'
            dialog.accept()
            t.equal(picker.pathDraft, '/tmp', 'accepted folder updates the editable absolute path')
            t.equal(host.requests, ['/tmp'], 'acceptance submits exactly one normalized folder')
            t.step(50, function () {
              t.check(picker.activeDialog === null, 'accepted dialog releases its popup')
              picker.choose()
              t.waitFor(function () {
                return picker.activeDialog && picker.activeDialog.visible
              }, 3000, 'chooser opens before hiding Settings', function () {
                window.visible = false
                t.step(100, function () {
                  t.check(picker.activeDialog === null, 'hiding Settings releases an open chooser')
                  window.visible = true
                  t.step(100, function () {
                    picker.choose()
                    t.waitFor(function () {
                      return picker.activeDialog && picker.activeDialog.visible
                    }, 3000, 'chooser reopens after its window was hidden', function () {
                      picker.activeDialog.reject()
                      t.equal(host.requests, ['/tmp'], 'window lifecycle and cancellation do not resubmit a folder')
                      t.done()
                    })
                  })
                })
              })
            })
          })
        })
      })
    })
  })
}
