// Persistent wallpaper contrast lifecycle; Bar retains layout and plugin API ownership.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: root
  visible: false

  // Current bar edge and thickness passed to the wallpaper contrast command.
  required property string position
  // Bar thickness supplied to each probe, without adding a size-change trigger.
  required property int barSize
  // Theme foreground and alternative used by the contrast command.
  required property color themeForeground
  // Alternative foreground when the theme text is unreadable on the wallpaper.
  required property color themeContrastForeground
  // Writable request state, exposed through Bar's existing public alias.
  property bool requestedTransparent: false
  // A valid probe has selected the transparent bar's foreground.
  property bool useTransparentForeground: false
  // Surface transparency applies immediately, independently of probe completion.
  property bool transparent: false
  // Retained probe result, reset to the current theme by an opaque request.
  property color transparentForeground: themeForeground
  // Color jumps suppress animation until two deferred turns have elapsed.
  property bool foregroundAnimationEnabled: true

  // Format a color (or color string) as #rrggbb.
  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string")
      c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  // Request a transparent or opaque bar; transparent applies at once, then the contrast probe refines the foreground.
  function setRequestedTransparency(value: bool): void {
    var nextTransparent = value
    root.requestedTransparent = nextTransparent
    if (!nextTransparent) {
      root.foregroundAnimationEnabled = false
      root.useTransparentForeground = false
      root.transparent = false
      root.transparentForeground = root.themeForeground
      root.restoreForegroundAnimation()
      return
    }
    // The surface must become transparent immediately.  The contrast-color
    // probe is asynchronous and should only refine the foreground color; it
    // must not leave an opaque bar behind while it runs or if it is delayed.
    root.transparent = true
    root.scheduleTransparentForegroundRefresh()
  }

  // Re-enable foreground animation two event-loop turns later, after the color jump has settled.
  function restoreForegroundAnimation(): void {
    Qt.callLater(function () {
      Qt.callLater(function () {
        root.foregroundAnimationEnabled = true
      })
    })
  }

  // Restart the debounce for the contrast probe, or reset the foreground when not transparent.
  function scheduleTransparentForegroundRefresh() {
    if (!root.requestedTransparent) {
      root.transparentForeground = root.themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  // Run omarchy-bar-text-color to pick a readable foreground over the wallpaper behind the bar.
  function refreshTransparentForeground(): void {
    if (!root.requestedTransparent || transparentForegroundProc.running)
      return
    transparentForegroundProc.command = ["omarchy-bar-text-color", root.position, String(root.barSize), root.colorHex(root.themeForeground), root.colorHex(root.themeContrastForeground)]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: root.scheduleTransparentForegroundRefresh()
  onPositionChanged: root.scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: root.scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: root.scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function (line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value))
          return
        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: Aranea.RuntimePaths.omarchyStateRoot + "/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }
}
