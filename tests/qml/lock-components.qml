// Behaviour contract for presentational lock components.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.lock" as LockComponents

ShellRoot {
  QmlTest {
    id: t
  }

  LockComponents.LockBranding {
    id: branding
    width: 800
    logoSource: "file:///tmp/unlock.png"
  }

  Component.onCompleted: {
    t.equal(branding.logoSource, "file:///tmp/unlock.png", "lock branding exposes its logo source")
    t.check(branding.implicitHeight > 0, "lock branding has measurable content")
    t.done()
  }
}
