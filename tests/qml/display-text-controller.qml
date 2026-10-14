// Catches lost last-wins queues, stuck failed previews, missing reflow and timeout.
import QtQuick
import Quickshell
import "lib"

ShellRoot {
  id: root
  // Real persistent text command owner.
  property var owner: null
  // Reflow notifications observed from the real owner.
  property int reflows: 0
  // Clock when the unconfirmed preview was requested.
  property double timeoutStarted: 0
  QmlTest {
    id: t
  }
  DisplayFixture {
    id: fixture
  }
  Component.onCompleted: fixture.configure({
    reset: true
  }, function () {
    var component = Qt.createComponent("plugins/araneadev.monitor/TextSizeController.qml")
    if (component.status !== Component.Ready) {
      t.check(false, "text owner accepts queued requests: " + component.errorString())
      t.done()
      return
    }
    root.owner = component.createObject(root, {
      baseFontSize: 12
    })
    owner.reflowRequested.connect(function () {
      root.reflows++
    })
    owner.adjustTextSize(1)
    owner.adjustTextSize(1)
    owner.adjustTextSize(99)
    owner.adjustTextSize(1)
    t.equal(owner.currentTextIndex(), 6, "latest text stop previews immediately")
    t.waitFor(function () {
      return fixture.state.textValues.length === 2
    }, 3000, "queued text command completes", function () {
      t.equal(fixture.state.textValues, [14, 20], "text queue applies first and last request only")
      t.equal(fixture.state.events, [["omarchy-display-text-size", "14"], ["omarchy-display-text-size", "20"]], "text command preserves exact argument arrays")
      t.equal(root.reflows, 3, "every accepted stop asks the panel to suppress reflow hover")
      owner.baseFontSize = 20
      t.equal(owner.textSizePreviewIndex, -1, "live base size confirms the pending stop")
      t.equal(root.reflows, 4, "live base-size reflow also notifies panel")
      fixture.configure({
        textFail: true
      }, function () {
        owner.requestTextStop(3)
        t.waitFor(function () {
          return owner.textSizePreviewIndex === -1
        }, 2000, "failed text command drops preview", function () {
          t.equal(owner.currentTextIndex(), 6, "failed text command shows the unchanged live size")
          fixture.configure({
            textFail: false,
            textDelay: 5.4
          }, function () {
            root.timeoutStarted = Date.now()
            owner.requestTextStop(4)
            owner.requestTextStop(5)
            t.equal(owner.textSizePreviewIndex, 5, "timeout scenario holds the newest queued preview")
            t.waitFor(function () {
              return owner.textSizePreviewIndex === -1
            }, 6000, "unconfirmed preview expires after five seconds", function () {
              t.check(Date.now() - root.timeoutStarted >= 4800, "preview remains available for the five-second confirmation window")
              t.equal(owner.currentTextIndex(), 6, "preview timeout returns to live base size")
              t.equal(owner.queuedTextPx, 0, "timeout drops work queued behind the unfinished command")
              t.waitFor(function () {
                return fixture.state.textValues.length === 3
              }, 2000, "accepted text command still completes after preview timeout", function () {
                t.step(250, function () {
                  t.equal(fixture.state.textValues, [14, 20, 14], "preview timeout prevents the discarded queued size from running")
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
