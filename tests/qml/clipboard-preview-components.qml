// Behaviour contract for the clipboard preview presentation.
import QtQuick
import Quickshell
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

  Component.onCompleted: {
    t.equal(preview.masked, true, "clipboard previews expose masking state")
    t.equal(preview.secretHint, "SPACE TO REVEAL", "clipboard previews expose secret guidance")
    t.equal(preview.textValue, "hidden", "clipboard previews expose text content")
    t.done()
  }
}
