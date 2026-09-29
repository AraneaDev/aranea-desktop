// Behaviour contract for presentational menu components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as MenuComponents

ShellRoot {
  QmlTest {
    id: t
  }

  MenuComponents.MenuRootTile {
    id: tile
    tileData: ({
        label: "Applications",
        detail: "Open apps",
        icon: "▦"
      })
    selected: true
  }

  MenuComponents.MenuAppLibrary {
    id: appLibrary
  }

  Component.onCompleted: {
    t.equal(tile.label, "Applications", "menu tiles expose their label")
    t.equal(tile.detail, "Open apps", "menu tiles expose their detail")
    t.equal(tile.selected, true, "menu tiles expose selection state")
    t.equal(appLibrary.entryName({
      name: "Terminal"
    }), "Terminal", "menu app libraries expose entry naming")
    t.done()
  }
}
