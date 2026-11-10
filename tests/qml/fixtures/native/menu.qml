// Exercise actual layer-shell card geometry across navigation and search.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host

  QmlTest {
    id: t
  }

  Menu.Menu {
    id: menu
    run: function (command) {
      t.check(false, "geometry acceptance never executes a menu action")
    }
  }

  // Locate the actual visible card, rather than recomputing its layout formula.
  function card() {
    var children = menu.view.contentItem.children
    for (var i = 0; i < children.length; i++)
      if (children[i].resultList !== undefined)
        return children[i]
    return null
  }

  // Measure after a production frame, not a timer that can race Qt's layout.
  function afterFrame(next) {
    var surface = host.card()
    var queued = surface && surface.grabToImage(function (result) {
      t.check(String(result.url).length > 0, "production menu frame rendered")
      next()
    })
    if (!queued) {
      t.check(false, "production menu frame capture queued")
      t.done()
    }
  }

  // Wait for layer configuration, then observe completed layout/render work.
  function centered(destination, label, next) {
    t.waitFor(function () {
      return menu.view && menu.view.visible && menu.view.height === menu.screenHeight
    }, 8000, label + " surface configured", function () {
      host.afterFrame(function () {
        t.equal(menu.activeMenu, destination, label + " destination selected")
        if (menu.activeMenu !== destination) {
          t.done()
          return
        }
        var surface = host.card()
        t.check(!!surface, label + " production card is present")
        if (!surface) {
          t.done()
          return
        }
        console.log("MENU GEOMETRY " + JSON.stringify({
          label: label,
          y: surface.y,
          height: surface.height,
          windowHeight: menu.view.height,
          screenHeight: menu.screenHeight,
          desiredHeight: menu.cardHeight,
          centeredTop: menu.view.centeredTop,
          effectiveTop: menu.view.effectiveCardTop,
          frozenTop: menu.view.cardTop,
          frozenRows: menu.view.maxRowsHeight,
          activeMenu: menu.activeMenu,
          filter: menu.filterText
        }))
        t.check(Math.abs(surface.y - (menu.view.height - surface.height) / 2) <= 1, label + " vertically centered")
        t.check(Math.abs(surface.x - (menu.view.width - surface.width) / 2) <= 1, label + " horizontally centered")
        next()
      })
    })
  }

  Component.onCompleted: t.waitFor(function () {
    return menu.menuSourcesReady && !!menu.item("appearance") && !!menu.item("settings")
  }, 8000, "shipped Appearance and consolidated Settings loaded", function () {
    console.log("NATIVE READY")
    menu.open('{"menu":"root"}')
    centered("root", "root", function () {
      menu.setActiveMenu("settings", true)
      centered("settings", "root to Settings", function () {
        menu.setActiveMenu("appearance", true)
        centered("appearance", "Settings to Appearance", function () {
          var top = host.card().y
          menu.setFilter("font")
          host.afterFrame(function () {
            t.equal(host.card().y, top, "typing preserves the search field position")
            menu.goBack()
            centered("settings", "back from filtered Appearance", function () {
              menu.open('{"menu":"appearance"}')
              centered("appearance", "summon Appearance while already open", function () {
                menu.open('{"mode":"input","prompt":"Name"}')
                centered("root", "replace open menu with input modal", function () {
                  menu.close()
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  })
}
