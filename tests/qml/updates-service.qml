// Real process-to-service transport, with only the package collector inert.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.updates" as Updates

ShellRoot {
  QmlTest {
    id: t
  }
  Updates.Service {
    id: service
    autoStart: false
    adapterPath: Qt.resolvedUrl("fixtures/update-status").toString().replace("file://", "")
  }
  Updates.Service {
    id: missing
    autoStart: false
    adapterPath: "/nonexistent/aranea-update-status"
  }
  Component.onCompleted: {
    missing.refresh()
    service.refresh()
    service.refresh()
    t.waitFor(function () {
      return !service.checking && service.status.count === 3 && missing.status.stale
    }, 4000, "package response reaches the service", function () {
      t.equal(service.status.groups.length, 2, "repository and AUR sources both reach the view")
      t.equal(service.status.error, "", "a valid collector response is successful")
      t.check(missing.status.error.length > 0, "failed collector startup reports an error")
      t.check(!missing.checking, "failed collector startup clears busy state")
      service.refresh()
      t.waitFor(function () {
        return !service.checking && service.status.stale
      }, 4000, "failed check completes", function () {
        t.equal(service.status.count, 3, "failed refresh retains the last valid package count")
        t.equal(service.status.error, "system check unavailable", "source failure reaches the panel")
        service.refresh()
        t.waitFor(function () {
          return !service.checking && service.status.count === 0
        }, 4000, "empty check completes", function () {
          t.equal(service.status.error, "", "successful no-update check clears the failure")
          t.check(!service.status.stale, "recovery clears stale state")
          t.done()
        })
      })
    })
  }
}
