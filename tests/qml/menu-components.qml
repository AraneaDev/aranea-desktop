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
    tileData: ({ label: "Applications", detail: "Open apps", icon: "▦" })
    selected: true
  }

  Component.onCompleted: {
    t.equal(tile.label, "Applications", "menu tiles expose their label")
    t.equal(tile.detail, "Open apps", "menu tiles expose their detail")
    t.equal(tile.selected, true, "menu tiles expose selection state")
    t.done()
  }
}
