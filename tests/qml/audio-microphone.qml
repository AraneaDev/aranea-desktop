// Microphone controls emit the intended input actions without changing output state.
import QtQuick
import QtTest
import Quickshell
import "lib"
import "plugins/araneadev.audio" as Audio

ShellRoot {
  QmlTest {
    id: t
  }
  // Captured channel actions for verification.
  property var actions: []
  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }
  FloatingWindow {
    implicitWidth: 360
    implicitHeight: 600
    visible: true
    Item {
      id: host
      width: 360
      height: 600
      Audio.AudioDropdown {
        id: dropdown
        width: parent.width
        view: ({
            inputVisible: true,
            input: {
              present: true,
              volume: 0.4,
              muted: false,
              level: 0,
              captureActive: true
            },
            inputDevices: [],
            outputDevices: [],
            streams: []
          })
        onAction: function (name, arg) {
          actions.push([name, arg])
        }
      }
    }
  }
  Component.onCompleted: t.step(350, function () {
    var section = t.findChild(dropdown, "inputSection")
    var mute = t.findChild(section, "microphoneMute")
    t.check(mute !== null, "microphone has an explicit mute control")
    if (mute) {
      t.check(mute.checked, "microphone switch is on when unmuted")
      mute.activate()
      t.equal(actions[actions.length - 1][0], "inputMute", "microphone switch dispatches input mute")
      dropdown.view = {
        inputVisible: true,
        input: {
          present: true,
          volume: 0.4,
          muted: true,
          level: 0,
          captureActive: true
        },
        inputDevices: [],
        outputDevices: [],
        streams: []
      }
      t.check(!mute.checked, "microphone switch follows observed mute")
      t.check(section.caption.indexOf("muted") !== -1, "recording with muted input is clearly labelled")
    }
    // Load the real badge rather than a fake bar widget or PipeWire service.
    var component = Qt.createComponent("plugins/araneadev.audio/AudioCaptureIndicator.qml")
    t.check(component.status === Component.Ready, "capture-only bar indicator is available")
    if (component.status === Component.Ready) {
      var badge = component.createObject(host, {
        captureActive: false,
        muted: false
      })
      t.check(!badge.visible, "idle unmuted microphone has no bar badge")
      badge.muted = true
      t.check(!badge.visible, "idle muted microphone has no bar badge")
      badge.captureActive = true
      t.check(badge.visible, "recorder activity shows the badge even with muted input")
      var mutedGlyph = badge.glyph
      badge.muted = false
      t.check(badge.glyph !== mutedGlyph, "active muted input and active live input use distinct glyphs")
      badge.captureActive = false
      t.check(!badge.visible, "ending capture removes the badge")
      badge.destroy()
    }
    if (!mute) {
      t.done()
      return
    }
    actions = []
    dropdown.noteLayoutChange()
    pointer.mouseClick(mute)
    t.equal(actions.length, 0, "microphone switch refuses a click during layout settling")
    t.step(350, function () {
      pointer.mouseClick(mute)
      t.equal(actions[actions.length - 1][0], "inputMute", "a settled pointer click toggles the microphone")
      t.done()
    })
  })
}
