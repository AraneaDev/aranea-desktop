// Behaviour contract for the clipboard preview presentation.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
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
      t.done()
    })
  }
}
