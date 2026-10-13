// Returning from search must restore the original emblem size and position.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  QmlTest {
    id: t
  }
  Menu.MenuCardChrome {
    id: chrome
    width: 760
    height: 300
    fullRootHeader: true
    rootHeaderHeight: 108
    motionEnabled: false
  }
  // Find the actual emblem image after header mode changes.
  function findSpider(item) {
    if (item instanceof Image)
      return item
    var children = t.childrenOf(item)
    for (var i = 0; i < children.length; i++) {
      var found = findSpider(children[i])
      if (found)
        return found
    }
    return null
  }
  Component.onCompleted: t.step(30, function () {
    var logo = findSpider(chrome)
    t.check(!!logo, "production header contains its spider image")
    if (!logo) {
      t.done()
      return
    }
    var originalWidth = logo.width
    var originalX = logo.parent.x
    chrome.fullRootHeader = false
    chrome.width = 540
    t.step(30, function () {
      t.check(logo.width < originalWidth, "search uses a compact spider")
      chrome.fullRootHeader = true
      chrome.width = 760
      t.step(30, function () {
        t.equal(logo.width, originalWidth, "returning from search restores the original spider width")
        t.equal(logo.parent.x, originalX, "returning from search restores the emblem position")
        t.check(logo.height <= chrome.rootHeaderHeight, "returned spider stays within the header")
        t.done()
      })
    })
  })
}
