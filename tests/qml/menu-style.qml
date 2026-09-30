// Behaviour of the menu's style object (MenuStyle.qml): the root header adds
// the context band, tiles and footer, fonts scale by 1.10, the three root
// tiles, and the minute clock only runs while the menu is open.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  QmlTest {
    id: t
  }

  Menu.MenuStyle {
    id: rootStyle
    fullRootHeader: true
  }

  Menu.MenuStyle {
    id: submenuStyle
    fullRootHeader: false
    opened: true
  }

  Component.onCompleted: {
    t.equal(rootStyle.rootExtrasHeight, rootStyle.rootContextHeight + rootStyle.rootTileHeight + rootStyle.footerHeight + rootStyle.contentSpacing * 3, "the root header adds the band, tiles and footer")
    t.equal(submenuStyle.rootExtrasHeight, 0, "submenus add nothing")
    t.equal(rootStyle.menuFontSize(10), 11, "font sizes scale by 1.10")
    t.equal(rootStyle.menuFontSize(0), 1, "and never reach zero")
    t.equal(rootStyle.rootTiles.length, 3, "three root tiles")
    t.equal(rootStyle.rootTiles[2].id, "tile.setup", "Setup is the third tile")
    t.equal(rootStyle.rootTiles[0].icon, String.fromCodePoint(0xF024B), "Files keeps its folder icon")
    t.equal(rootStyle.rootTiles[1].icon, "", "Terminal keeps its icon")
    t.equal(rootStyle.rootTiles[2].icon, "", "Setup keeps its icon")
    t.check(/^\d\d:\d\d$/.test(rootStyle.clockContext), "the clock reads HH:mm")
    t.equal(rootStyle.menuClock.enabled, false, "the clock is off while closed")
    t.equal(submenuStyle.menuClock.enabled, true, "and on while open")
    t.done()
  }
}
