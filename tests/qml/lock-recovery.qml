// Production lock timer, PAM failure and video-poster behavior with inert native boundaries.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.lock" as Lock

ShellRoot {
  QmlTest {
    id: t
  }
  Lock.Service {
    id: service
  }

  Process {
    id: restorePoster
    command: ["touch", Quickshell.env("ARANEA_TEST_SANDBOX") + "/poster-ready"]
    onExited: service.refreshBackground()
  }

  // Finds the real service timer by its wall-clock suspend timestamp.
  function blankTimer() {
    var children = t.childrenOf(service)
    for (var i = 0; i < children.length; i++)
      if (children[i].armedAt !== undefined)
        return children[i]
    return null
  }

  // Reads the actual LockView bindings mounted in both native lock and preview.
  function lockViews(item) {
    var found = []
    var children = t.childrenOf(item)
    for (var i = 0; i < children.length; i++) {
      var child = children[i]
      if (child.loadBackground !== undefined && child.backgroundPath !== undefined)
        found.push(child)
      found = found.concat(lockViews(child))
    }
    return found
  }

  // Finds an Image whose live source is the cached still rather than the video.
  function hasPosterImage(item) {
    var children = t.childrenOf(item)
    for (var i = 0; i < children.length; i++) {
      if (children[i].fillMode !== undefined && String(children[i].source).indexOf("/poster-other.webm.png?v=") >= 0)
        return true
      if (hasPosterImage(children[i]))
        return true
    }
    return false
  }

  Component.onCompleted: t.step(200, function () {
    var timer = blankTimer()
    t.check(timer !== null, "production idle blank timer is mounted")
    var blank = t.childrenOf(service).filter(function (child) {
      return child.command && child.command.join(" ").indexOf("omarchy-brightness-keyboard off") >= 0
    })[0]
    service.lockRequested = true
    service.armBlankTimer()
    t.equal(timer.interval, 5000, "ordinary blank delay is five seconds")
    timer.armedAt = Date.now() - 8000
    timer.triggered()
    t.equal(timer.interval, 15000, "suspend-delayed timeout grants fifteen seconds")
    t.check(!blank.running, "resume detection never blanks the freshly woken panel")
    t.check(timer.running && Date.now() - timer.armedAt < 1000, "resume grace is freshly armed")
    service.runWake()
    t.equal(timer.interval, 5000, "ordinary activity returns to five seconds")
    service.fingerprintAuthenticating = true
    timer.triggered()
    t.check(blank.running, "ordinary idle timeout blanks even while fingerprint PAM waits")
    service.fingerprintAuthenticating = false
    service.authenticatingPassword = true
    t.check(!timer.running, "password authentication holds blanking")
    service.enteredPassword = "secret"
    service.pendingPassword = "secret"
    service.handlePasswordFailure()
    t.check(!service.authenticatingPassword && timer.running, "failed auth reenables input and blank countdown")
    t.equal(service.enteredPassword, "", "failed auth clears the input")
    t.equal(service.pendingPassword, "", "failed auth clears the PAM secret")
    t.equal(service.failureMessage, "Authentication failed (1)", "failed auth reports the actual attempt")
    service.lockRequested = false
    timer.stop()
    service.previewVisible = true
    service.backgroundPath = "/fixture/photo.png"
    t.equal(service.lockBackgroundPath, "/fixture/photo.png", "image backgrounds use their original still")
    service.backgroundPath = "/fixture/delayed.mp4"
    t.equal(service.lockBackgroundPath, "", "video never reaches the Image while its poster is pending")
    service.backgroundPath = "/fixture/other.webm"
    t.waitFor(function () {
      return service.lockBackgroundPath.endsWith("/poster-other.webm.png")
    }, 2000, "latest video gets a cached still after an in-flight change", function () {
      t.check(service.lockBackgroundPath !== service.backgroundPath, "video resolves to the host cached still")
      var views = lockViews(service)
      t.equal(views.length, 2, "production lock and preview views are mounted")
      t.check(views.every(function (view) {
        return view.backgroundPath === service.lockBackgroundPath
      }), "both real lock views receive only the still")
      t.check(hasPosterImage(service), "the real Image source loads the cached poster")
      service.backgroundPath = "/fixture/bad.mp4"
      t.step(250, function () {
        t.check(service.lockBackgroundPath.endsWith("/poster-other.webm.png"), "failed poster refresh retains the last-good still")
        service.backgroundPath = "/fixture/photo.png"
        t.equal(service.lockBackgroundPath, "/fixture/photo.png", "switching back to an image releases the video poster")
        service.backgroundPath = Quickshell.env("ARANEA_TEST_SANDBOX") + "/recover.mp4"
        t.step(250, function () {
          t.equal(service.lockBackgroundPath, "", "a first helper failure keeps the plain fallback")
          restorePoster.running = true
          t.waitFor(function () {
            return service.lockBackgroundPath.endsWith("/poster-recover.mp4.png")
          }, 2000, "explicit background refresh retries an unchanged video after helper recovery", function () {
            t.done()
          })
        })
      })
    })
  })
}
