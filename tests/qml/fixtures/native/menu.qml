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

  // Allow guards and layer configuration to settle before measuring the card.
  function centered(label, next) {
    t.waitFor(function () {
      return menu.view && menu.view.visible && menu.view.height === menu.screenHeight
    }, 8000, label + " surface configured", function () {
      t.step(300, function () {
        var surface = host.card()
        t.check(!!surface, label + " production card is present")
        if (!surface) {
          t.done()
          return
        }
        t.check(Math.abs(surface.y - (menu.view.height - surface.height) / 2) <= 1, label + " vertically centered")
        t.check(Math.abs(surface.x - (menu.view.width - surface.width) / 2) <= 1, label + " horizontally centered")
        next()
      })
    })
  }

  Component.onCompleted: t.waitFor(function () {
    return menu.menuSourcesReady
  }, 8000, "shipped menu sources loaded", function () {
    console.log("NATIVE READY")
    menu.open('{"menu":"root"}')
    centered("root", function () {
      menu.setActiveMenu("settings", true)
      centered("root to Settings", function () {
        menu.setActiveMenu("appearance", true)
        centered("Settings to Appearance", function () {
          var top = host.card().y
          menu.setFilter("font")
          t.step(300, function () {
            t.equal(host.card().y, top, "typing preserves the search field position")
            menu.goBack()
            centered("back from filtered Appearance", function () {
              menu.open('{"menu":"appearance"}')
              centered("summon Appearance while already open", function () {
                menu.open('{"mode":"input","prompt":"Name"}')
                centered("replace open menu with input modal", function () {
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
