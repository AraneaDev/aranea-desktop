// Matched queries render safely inside existing chrome geometry; special modes retain their layout.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  QtObject {
    id: library
    signal appsChanged
    function entryName(entry) {
      return entry.name
    }
    function entrySubtext(entry) {
      return 'Launch application'
    }
    function sortedEntries(query) {
      return [
        {
          entry: {
            id: 'browser',
            name: '<b>Project</b>'
          }
        }
      ]
    }
    function refreshIcons() {
    }
    function iconSource(icon) {
      return ''
    }
    function launch(id, label) {
      t.check(false, 'query presentation never launches')
    }
  }
  QtObject {
    id: scoped
    property var appLibrary: library
  }
  Menu.Menu {
    id: menu
    shell: scoped
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl('fixtures/omarchy-menu.jsonc').toString().replace('file://', '')
    run: function (command) {
      t.check(false, 'query presentation never dispatches')
    }
  }
  FloatingWindow {
    implicitWidth: 520
    implicitHeight: 600
    visible: true
    Menu.MenuSurface {
      id: surface
      root: menu
      width: menu.cardWidth
      height: menu.cardHeight
    }
  }
  // Checks the actual rendered header instead of a separate query helper.
  function assertHeader(query) {
    var title = t.findChild(surface, 'menuHeaderTitle')
    t.check(!!title && title.text === '› ' + query, 'matched query is visible in production header')
    if (!title)
      return
    t.equal(title.textFormat, Text.PlainText, 'markup-shaped query is rendered as plain text')
    t.check(title.visible && title.width > 0, 'query text has visible bounded geometry')
    var point = title.mapToItem(surface, 0, 0)
    t.check(point.x >= 0 && point.x + title.width <= surface.width && point.y >= 0, 'query header stays within card')
    t.equal(menu.style.chromeHeight, menu.style.headerHeight, 'query retains compact chrome height')
  }
  Component.onCompleted: {
    menu.desktopSearch.compositor = null
    menu.openRoute('root')
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened
    }, 10000, 'menu sources load', function () {
      menu.setFilter('<b>Project</b>')
      t.check(menu.displayModel.count > 0, 'markup-shaped query has an actual matching result')
      t.step(50, function () {
        assertHeader('<b>Project</b>')
        menu.openRoute('system')
        menu.setFilter('lock')
        t.step(50, function () {
          assertHeader('lock')
          t.check(t.findChild(surface, 'searchEverywhere').visible, 'scoped query retains global-search affordance')
          menu.setFilter('zzzz no matches')
          t.step(50, function () {
            var title = t.findChild(surface, 'menuHeaderTitle')
            t.check(!title || title.text.indexOf('zzzz') < 0, 'no-match presentation retains its existing query location')
            menu.mode = 'input'
            menu.setFilter('<b>value</b>')
            t.step(50, function () {
              t.check(!title || title.text.indexOf('<b>value</b>') < 0, 'input mode retains separate input line')
              menu.mode = 'select'
              t.step(50, function () {
                t.check(!title || title.text.indexOf('<b>value</b>') < 0, 'dmenu retains prompt header')
                t.done()
              })
            })
          })
        })
      })
    })
  }
}
