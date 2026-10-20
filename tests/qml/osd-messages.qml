// Message OSDs must not look like volume gauges. Exercise the real panel
// with shutdown/logout/reboot payloads, without executing session commands.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.osd" as Osd

ShellRoot {
  QmlTest {
    id: t
  }

  Osd.Osd {
    id: osd
    motionEnabled: false
  }

  Component.onCompleted: {
    osd.show("volume", "", "62", "100", "62%", "0")
    var strand = t.findChild(osd, "osdStrandTrack").parent
    t.check(strand.visible, "volume shows its level gauge")
    t.equal(osd.message, "62%", "volume keeps its percentage")
    var volumeWidth = osd.contentWidth
    var actions = ["shutdown", "reboot", "logout"]
    for (var i = 0; i < actions.length; i++) {
      osd.open(JSON.stringify({
        icon: actions[i],
        message: "Session ending",
        value: "",
        max: "100",
        duration: "5000"
      }))
      t.check(osd.opened && !osd.hasProgress, actions[i] + " opens a message")
      t.check(!strand.visible, actions[i] + " hides the level gauge")
      t.equal(osd.contentWidth, osd.iconWidth + osd.gap + osd.messageWidth, actions[i] + " reserves only icon and message space")
    }
    osd.show("volume", "", "62", "100", "62%", "0")
    t.check(strand.visible, "volume restores the level gauge after a message")
    t.equal(osd.contentWidth, volumeWidth, "volume restores its complete layout")
    osd.close()
    t.done()
  }
}
