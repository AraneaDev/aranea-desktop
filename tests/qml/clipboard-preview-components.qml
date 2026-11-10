// Behaviour contract for the clipboard preview presentation.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.clipboard" as Clipboard
import "plugins/araneadev.shared" as Aranea
import "plugins/araneadev.clipboard/components" as ClipboardComponents

ShellRoot {
  QmlTest {
    id: t
  }

  ClipboardComponents.ClipboardPreview {
    id: preview
    masked: true
    secretHint: "SPACE TO REVEAL"
    textValue: "hidden"
  }

  Clipboard.Clipboard {
    id: clip
    windowEnabled: false
    captureEnabled: false
    historyPath: Quickshell.env("HOME") + "/preview-history.json"
  }
  FloatingWindow {
    visible: true
    implicitWidth: 400
    implicitHeight: 300
    ClipboardComponents.ClipboardResultsPane {
      id: pane
      width: 200
      height: 240
      model: clip.displayModel
      selectedIndex: clip.selectedIndex
      emptyMessage: "No matches for “" + clip.filterText + "”"
    }
    Aranea.EmptyState {
      id: narrow
      x: 250
      width: 100
      height: 240
      message: pane.emptyMessage
    }
  }
  // Walk the real pane content, including its preview and empty-state labels.
  function descendants(item) {
    var result = []
    t.childrenOf(item).forEach(function (child) {
      result.push(child)
      result = result.concat(descendants(child))
    })
    return result
  }
  // Drive a real long query and inspect layout before restoring a selection.
  function checkEmptyLayout() {
    clip.loadHistory(JSON.stringify([
      {
        type: "text",
        text: "A matching note",
        capturedAtMs: Date.now()
      }
    ]))
    clip.setFilter("z".repeat(1000))
    t.step(100, function () {
      t.equal(clip.displayModel.count, 0, "1000-character no-match query empties the real result model")
      var previewItem = descendants(pane).find(function (item) {
        return item.textValue !== undefined && item.secretHint !== undefined
      })
      t.check(previewItem && !previewItem.visible, "empty results paint no preview or separator")
      var cards = [pane, narrow]
      cards.forEach(function (card) {
        var labels = descendants(card).filter(function (item) {
          return item.text === pane.emptyMessage
        })
        t.equal(labels.length, 1, "empty card has its existing no-match message")
        labels.forEach(function (label) {
          var point = label.mapToItem(card, 0, 0)
          t.check(point.x >= 0 && point.x + label.width <= card.width, "empty message bounds stay within available card width")
          t.check(label.paintedWidth <= label.width, "long no-match message elides within text bounds")
        })
      })
      clip.setFilter("")
      t.step(100, function () {
        t.equal(clip.displayModel.count, 1, "clearing the query restores the result")
        t.check(previewItem && previewItem.visible, "populated results restore selected preview")
        t.done()
      })
    })
  }

  // Unmasked preview used to find the first-line text and check its cap top
  // against firstLineTop (clipboard-3).
  ClipboardComponents.ClipboardPreview {
    id: firstLinePreview
    firstLineTop: 12
    textValue: "hello world"
  }

  // Ink metrics matching firstLinePreview's own text font (title size, its
  // default fontFamily, isCode false).
  TextMetrics {
    id: firstLineInk
    font.family: firstLinePreview.fontFamily
    font.pixelSize: Style.font.title
    text: "H"
  }

  Component.onCompleted: {
    t.equal(preview.masked, true, "clipboard previews expose masking state")
    t.equal(preview.secretHint, "SPACE TO REVEAL", "clipboard previews expose secret guidance")
    t.equal(preview.textValue, "hidden", "clipboard previews expose text content")

    t.step(50, function () {
      var target = null
      for (var i = 0; i < firstLinePreview.children.length; i++) {
        if (firstLinePreview.children[i].text === firstLinePreview.textValue)
          target = firstLinePreview.children[i]
      }
      t.check(!!target, "clipboard preview exposes its first-line text")
      if (target) {
        var capTop = target.y + target.baselineOffset + firstLineInk.tightBoundingRect.y
        t.check(Math.abs(capTop - firstLinePreview.firstLineTop) <= 0.5, "clipboard preview's first line cap top follows firstLineTop: " + capTop)
      }
      checkEmptyLayout()
    })
  }
}
