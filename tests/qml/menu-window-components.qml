// Behaviour contracts for the larger menu-window presentation components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as MenuComponents

ShellRoot {
  QmlTest { id: t }

  MenuComponents.MenuCardChrome {
    id: chrome
    fullRootHeader: true
    activeTitle: "SYSTEM"
    hint: "ENTER OPEN"
    rootTiles: [{ label: "Apps", detail: "Launch", icon: "▦" }]
  }

  MenuComponents.MenuResultList {
    id: results
    selectedIndex: 1
    cursorActive: true
  }

  Component.onCompleted: {
    t.equal(chrome.fullRootHeader, true, "menu chrome exposes root-header state")
    t.equal(chrome.rootTiles.length, 1, "menu chrome exposes root tiles")
    t.equal(results.selectedIndex, 1, "menu result lists expose selection state")
    t.equal(results.cursorActive, true, "menu result lists expose cursor state")
    t.done()
  }
}
