// Command rows retain vertical order, stable keyed clicks, and keyboard focus while scrolling.
import QtQuick
import Quickshell
import QtTest
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  QmlTest {
    id: t
  }
  TestCase {
    id: pointer
    when: false
  }
  ListModel {
    id: rows
  }
  // Record activation without launching an application.
  property var activated: []
  FloatingWindow {
    visible: true
    implicitWidth: 540
    implicitHeight: 200
    Menu.MenuResultList {
      id: results
      anchors.fill: parent
      model: rows
      fullRootHeader: true
      rowHeightForDetail: function () {
        return 58
      }
      onRowActivated: function (index, key) {
        activated = [index, key]
      }
    }
  }
  Component.onCompleted: {
    for (var i = 0; i < 5; i++)
      rows.append({
        itemId: "command." + i,
        kind: "action",
        icon: "A",
        iconFont: "",
        appIcon: "",
        appId: "",
        label: "Command " + i,
        detail: "Description",
        childCount: 0,
        section: ""
      })
    t.waitFor(function () {
      return results.list.itemAtIndex(2) !== null
    }, 3000, "visible commands render", function () {
      var first = results.list.itemAtIndex(0)
      var second = results.list.itemAtIndex(1)
      t.equal(first.x, second.x, "commands share one column")
      t.check(second.y >= first.y + first.height, "commands retain vertical order")
      t.check(results.list.contentHeight > results.list.height, "overflow remains scrollable")
      t.step(350, function () {
        pointer.mouseClick(second, 40, second.height / 2)
        t.equal(activated, [1, "command.1"], "click retains original command identity")
        results.selectedIndex = 4
        results.cursorActive = true
        results.list.positionViewAtIndex(4, ListView.Contain)
        t.waitFor(function () {
          return results.list.itemAtIndex(4) !== null
        }, 3000, "last command renders after scrolling", function () {
          var last = results.list.itemAtIndex(4)
          t.check(t.findChild(last, "cursorOutline").focused, "keyboard focus follows selected command")
          t.check(last.y >= results.list.contentY && last.y + last.height <= results.list.contentY + results.list.height, "selected command stays visible")
          t.done()
        })
      })
    })
  }
}
