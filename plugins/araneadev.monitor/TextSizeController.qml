// Persistent text-size command owner; the Panel owns hover and input policy.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
  id: root
  visible: false
  // Live shell size, supplied by the persistent Panel.
  property real baseFontSize: 12
  // Base-size initialization must not create a synthetic startup reflow.
  property bool _initialized: false
  // Ask the Panel to apply its layout and hover policy.
  signal reflowRequested
  Component.onCompleted: _initialized = true

  // Text size slider: curated macOS-style notches (px). The panel snaps to
  // these stops; the CLI (omarchy-display-text-size) accepts any integer in range.
  readonly property var textSizeStops: [9, 10, 11, 12, 14, 16, 20]
  // While a change is in flight, the chosen stop index overrides the live
  // base-size so the knob doesn't snap back during the file round-trip. -1 =
  // no pending change; follow Style.font.baseSize.
  property int textSizePreviewIndex: -1
  // A text size (px) asked for while textScaleProc was already running, run
  // when it exits (the last one wins); 0 for none.
  property int queuedTextPx: 0

  // ---- Text size (shell base font + GTK text-scaling, via one CLI) ----
  // The index into textSizeStops nearest to px.
  function nearestTextStop(px) {
    var best = 0
    var bestDist = 1e9
    for (var i = 0; i < textSizeStops.length; i++) {
      var d = Math.abs(textSizeStops[i] - px)
      if (d < bestDist) {
        bestDist = d
        best = i
      }
    }
    return best
  }

  // Effective stop index: the pending choice while a change is in flight,
  // otherwise whatever Style's live base-size rounds to.
  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextStop(root.baseFontSize)
  }

  // Applies px via omarchy-display-text-size; a request while it runs is
  // queued, the last one winning.
  function setTextSize(px) {
    if (textScaleProc.running) {
      root.queuedTextPx = px
      return
    }
    textScaleProc.command = ["omarchy-display-text-size", String(px)]
    textScaleProc.running = true
  }

  // Moves the text-size stop by deltaSteps, previewing it at once while the
  // CLI round-trips. Nothing at either end.
  function adjustTextSize(deltaSteps) {
    var idx = currentTextIndex() + deltaSteps
    if (idx < 0)
      idx = 0
    if (idx > textSizeStops.length - 1)
      idx = textSizeStops.length - 1
    if (idx === currentTextIndex())
      return
    requestTextStop(idx)
  }

  // Asks for text stop IDX: previews it at once (pulsing busy) and runs
  // the CLI; textPreviewTimeout drops the preview if the base size never
  // follows.
  function requestTextStop(idx) {
    root.reflowRequested()
    textSizePreviewIndex = idx
    textPreviewTimeout.restart()
    setTextSize(textSizeStops[idx])
  }

  // The base size never followed a text-size request within 5 s: drops
  // the preview and any queued size, so the slider shows the real size.
  function textPreviewTimedOut() {
    root.textSizePreviewIndex = -1
    root.queuedTextPx = 0
  }

  // textScaleProc exited with EXITCODE: runs the queued size, else drops a
  // preview the CLI failed on or that Style already shows.
  function textScaleExited(exitCode) {
    if (root.queuedTextPx > 0) {
      var px = root.queuedTextPx
      root.queuedTextPx = 0
      setTextSize(px)
      return
    }
    if (exitCode !== 0 || (root.textSizePreviewIndex >= 0 && nearestTextStop(root.baseFontSize) === root.textSizePreviewIndex))
      root.textSizePreviewIndex = -1
  }

  // Applies text size via the CLI, which rewrites the shell override file;
  // Style picks the new base-size up through its own file watch, so there's
  // nothing to refresh here.
  // qmllint disable signal-handler-parameters
  Process {
    id: textScaleProc
    stdout: StdioCollector {
      waitForEnd: true
    }
    onExited: function (exitCode) {
      root.textScaleExited(exitCode)
    }
  }

  // qmllint enable signal-handler-parameters

  // Drops a text-size preview the base size never followed (see
  // textPreviewTimedOut).
  Timer {
    id: textPreviewTimeout
    interval: 5000
    repeat: false
    onTriggered: if (root.textSizePreviewIndex >= 0)
      root.textPreviewTimedOut()
  }

  onBaseFontSizeChanged: {
    if (!_initialized)
      return
    root.reflowRequested()
    if (root.textSizePreviewIndex >= 0 && root.nearestTextStop(root.baseFontSize) === root.textSizePreviewIndex)
      root.textSizePreviewIndex = -1
  }
}
