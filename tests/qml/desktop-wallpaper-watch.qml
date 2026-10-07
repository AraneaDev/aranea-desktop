// Filesystem-backed wallpaper observation: replacing a symlink triggers readback.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.menu" as Menu
import "plugins/araneadev.shared" as Shared

ShellRoot {
  id: fixture
  // Narrow adapter calls observed after a filesystem event.
  property int reads: 0
  // Repeated replacements prove that the directory watcher remains armed.
  property int replacements: 0
  QmlTest {
    id: t
  }
  Menu.DesktopWallpaperActions {
    id: owner
    runner: function (argv, done) {
      fixture.reads += 1
      if (argv[1] === "list")
        done(0, '[]', "")
      else if (argv[1] === "status")
        done(0, '{"availability":"available","activeId":null}', "")
      else
        done(0, '{"enabled":false}', "")
    }
  }
  Process {
    id: setup
    command: ["/bin/sh", "-c", 'mkdir -p "$1/current"; printf same > "$1/a"; printf same > "$1/b"; ln -s "$1/a" "$1/current/background"', "wallpaper-watch", Shared.RuntimePaths.omarchyStateRoot]
    // Exit status enum is absent from Quickshell type metadata.
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      t.equal(code, 0, "isolated background fixture created")
      owner.active = true
      t.waitFor(function () {
        return fixture.reads >= 3
      }, 3000, "initial snapshot", function () {
        t.step(250, function () {
          fixture.reads = 0
          replace.running = true
        })
      })
    }
    // qmllint enable signal-handler-parameters
  }
  Process {
    id: replace
    command: ["/bin/sh", "-c", 'ln -s "$1/b" "$1/current/next"; mv -Tf "$1/current/next" "$1/current/background"', "wallpaper-watch", Shared.RuntimePaths.omarchyStateRoot]
    // qmllint disable signal-handler-parameters
    onExited: function (code) {
      t.equal(code, 0, "background symlink replaced with identical-content target")
      t.waitFor(function () {
        return fixture.reads >= 3
      }, 3000, "replacement triggers authoritative readback", function () {
        fixture.replacements += 1
        if (fixture.replacements === 2) {
          t.done()
        } else {
          t.step(150, function () {
            fixture.reads = 0
            replace.running = true
          })
        }
      })
    }
    // qmllint enable signal-handler-parameters
  }
  Component.onCompleted: setup.running = true
}
