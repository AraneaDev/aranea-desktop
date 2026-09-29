// Behaviour contract for presentational bar components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as BarComponents

ShellRoot {
  QmlTest {
    id: t
  }

  BarComponents.TooltipBubble {
    id: bubble
    text: "Workspace"
  }

  Component.onCompleted: {
    t.equal(bubble.text, "Workspace", "bar tooltips expose their text")
    t.check(bubble.implicitWidth > 0, "bar tooltips have a measurable width")
    t.done()
  }
}
