// Real pointer and keyboard selection must stay local and respect layout settling.
import QtQuick
import QtTest
import Quickshell
import qs.Ui
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Requests emitted by the real page, never executed by a helper.
  property var requests: []
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    name: "thumbnailPointer"
    when: false
  }
  FloatingWindow {
    implicitWidth: 600
    implicitHeight: 700
    visible: true
    PointerMoveGate {
      id: gate
      referenceItem: page
      property real layoutChangedAt: 0
    }
    Settings.AppearancePage {
      id: page
      width: 560
      pointerGate: gate
      backendState: ({
          wallpaper: {
            activeId: 'day',
            availability: 'available'
          },
          wallpapersAvailability: 'available',
          wallpapers: [
            {
              id: 'day',
              label: 'Day',
              path: '',
              available: true
            },
            {
              id: 'night',
              label: 'Night',
              path: '',
              available: true
            }
          ],
          schedule: {
            enabled: true
          },
          motion: {
            configured: 'on',
            applied: 'on',
            availability: 'available'
          }
        })
      onRequest: function (operation, args) {
        host.requests = host.requests.concat([[operation, args]])
      }
    }
  }
  // Locate the catalog option without assuming the preview's control type.
  function option(item, id) {
    if (item.modelData && item.modelData.id === id)
      return item
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++) {
      var found = option(kids[i], id)
      if (found)
        return found
    }
    return null
  }
  Component.onCompleted: t.step(400, function () {
    var target = option(page, 'night').children[0]
    page.selectWallpaper('day')
    pointer.mouseMove(target, target.width / 2, target.height / 2)
    gate.reset()
    gate.layoutChangedAt = Date.now()
    pointer.mouseClick(target, target.width / 2, target.height / 2)
    t.equal(page.selectedId, 'day', 'stationary thumbnail click within 300ms of layout shift is refused')
    t.step(400, function () {
      pointer.mouseClick(target, target.width / 2, target.height / 2)
      t.equal(page.selectedId, 'night', 'settled pointer click selects the wallpaper image')
      t.equal(page.appliedId, 'day', 'image selection preserves owner wallpaper')
      t.equal(requests.length, 0, 'thumbnail click emits no mutation')
      var label = option(page, 'day').children[1]
      label.forceActiveFocus()
      pointer.keyClick(Qt.Key_Return)
      t.equal(page.selectedId, 'day', 'existing label keyboard selection remains available')
      t.equal(requests.length, 0, 'keyboard selection emits no mutation')
      var note = t.findChild(page, 'wallpaperScheduleNote')
      t.check(!!note && note.visible && note.text.indexOf('next phase') >= 0, 'enabled schedule explains the manual wallpaper override')
      page.backendState = Object.assign({}, page.backendState, {
        schedule: {
          enabled: false
        }
      })
      t.check(!note || !note.visible, 'disabled schedule hides the override note')
      page.applyWallpaper()
      t.equal(requests, [['set wallpaper', ['day']]], 'only explicit Apply dispatches the selected wallpaper')
      t.done()
    })
  })
}
