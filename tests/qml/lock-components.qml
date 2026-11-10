// Real lock input restores focus after Window changes and failed authentication.
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
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 800
    implicitHeight: 600
    Item {
      id: other
      focus: false
    }
    LockComponents.LockView {
      id: view
      anchors.fill: parent
      loadBackground: false
    }
  }

  // Locate the actual password TextInput, rather than a simulated focus flag.
  function passwordField(item) {
    var children = t.childrenOf(item)
    for (var i = 0; i < children.length; i++) {
      if (children[i].echoMode === TextInput.Password)
        return children[i]
      var found = passwordField(children[i])
      if (found)
        return found
    }
    return null
  }

  Component.onCompleted: t.step(150, function () {
    t.equal(branding.logoSource, "file:///tmp/unlock.png", "lock branding exposes its logo source")
    t.check(branding.implicitHeight > 0, "lock branding has measurable content")
    var field = passwordField(view)
    t.check(field !== null, "production password field is mounted")
    view.forcePasswordFocus()
    t.check(field.activeFocus, "input starts focused")
    other.forceActiveFocus()
    t.step(50, function () {
      t.check(field.activeFocus, "Window focus loss restores password input")
      view.authenticatingPassword = true
      other.forceActiveFocus()
      view.forcePasswordFocus()
      t.step(50, function () {
        t.check(!field.enabled, "authentication disables the real input")
        t.check(other.activeFocus && !field.activeFocus, "disabled authentication input never steals focus")
        view.authenticatingPassword = false
        view.failureMessage = "Authentication failed (1)"
        t.step(50, function () {
          t.check(field.enabled && field.activeFocus, "failed authentication restores usable input")
          view.inputEnabled = false
          other.forceActiveFocus()
          view.forcePasswordFocus()
          t.step(50, function () {
            t.check(other.activeFocus && !field.activeFocus, "preview or inactive lock never steals focus")
            t.done()
          })
        })
      })
    })
  })
}
