// Real host cache pruning must not leave the service pointing at a deleted still.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.lock" as Lock

ShellRoot {
  id: root
  // Successful A poster, before obsolete B evicts it.
  property string firstPoster: ""
  // All extraction inputs and synchronization files are private to this run.
  readonly property string directory: Quickshell.env("ARANEA_TEST_SANDBOX")
  QmlTest {
    id: t
  }
  Lock.Service {
    id: service
  }
  FileView {
    id: started
    path: root.directory + "/started-B"
    printErrors: false
  }
  FileView {
    id: failed
    path: root.directory + "/failed-C"
    printErrors: false
  }
  FileView {
    id: previous
    path: root.firstPoster
    printErrors: false
    blockLoading: true
    blockAllReads: true
  }
  Process {
    id: release
    command: ["touch", root.directory + "/release-B"]
  }
  Component.onCompleted: t.step(200, function () {
    service.backgroundPath = root.directory + "/A.mp4"
    service.refreshPoster()
    t.waitFor(function () {
      return service.videoPosterPath !== ""
    }, 2000, "A extracts", function () {
      root.firstPoster = service.videoPosterPath
      previous.reload()
      previous.data()
      t.check(previous.loaded, "A is an actual cached file")
      service.backgroundPath = root.directory + "/B.mp4"
      t.waitFor(function () {
        started.reload()
        return started.loaded
      }, 2000, "B starts extraction", function () {
        service.backgroundPath = root.directory + "/C.mp4"
        release.running = true
        t.waitFor(function () {
          failed.reload()
          return failed.loaded
        }, 2000, "C is retried and fails", function () {
          t.step(100, function () {
            previous.reload()
            previous.data()
            t.check(!previous.loaded, "real helper success B prunes cached A")
            t.equal(service.videoPosterPath, "", "obsolete B and failed C leave a valid plain fallback")
            t.equal(service.lockBackgroundPath, "", "lock image never retains the deleted A path")
            t.done()
          })
        })
      })
    })
  })
}
