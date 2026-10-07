// Compact shared rows keep labels separate from long detail and trailing actions.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Shared
import qs.Commons

ShellRoot {
  QmlTest {
    id: t
  }
  Shared.NodeDeviceRow {
    id: row
    refined: true
    width: 300
    label: "Studio monitor interface"
    detail: "Unavailable while the wireless adapter is restarting"
    Shared.FilamentPill {
      id: action
      text: "Retry"
      width: 52
      height: 28
      refined: true
    }
  }
  Shared.DropdownHeader {
    id: header
    width: 300
    refined: true
    title: "A long connected device heading"
    caption: "Current state and recovery context"
    Shared.FilamentSwitch {
      id: toggle
    }
  }
  // Retrieve production text without requiring test-specific presentation IDs.
  function textChild(item, text) {
    return t.childrenOf(item).find(function (child) {
      return child.text === text
    })
  }
  Timer {
    interval: 150
    running: true
    onTriggered: {
      var label = textChild(row, row.label)
      var detail = t.findChild(row, "detailText")
      var trailing = t.findChild(row, "rowTrailing")
      t.check(label.width >= row.width * 0.25, "long detail preserves a readable primary label column")
      t.check(detail.width <= row.width * 0.4, "secondary text has a bounded column")
      t.check(detail.elide === Text.ElideRight, "long secondary context elides rather than overlapping")
      t.check(label.x + label.width < detail.x, "label and detail remain separate")
      t.check(detail.x + detail.width < trailing.x, "detail leaves room for trailing action")
      t.equal(action.height, 28, "refinement preserves pointer target height")
      row.width = 240
      t.step(20, function () {
        t.check(label.width > 0 && detail.width > 0, "compact viewport retains positive text widths")
        detail.font.pixelSize = 24
        t.step(20, function () {
          t.check(label.width > 0 && detail.width <= row.width * 0.4, "larger secondary font stays inside its column")
          t.check(header.implicitHeight > 0 && toggle.width > 0, "header retains title and trailing control geometry")
          t.done()
        })
      })
    }
  }
}
