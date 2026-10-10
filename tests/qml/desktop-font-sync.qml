// Font projections coalesce family/size changes and serialize in-flight updates.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "lib"
import "plugins/araneadev.shared" as Shared

ShellRoot {
  id: root
  // Recorded mutations and manually completed process boundary.
  property var calls: []
  // Completion callback retained until the test releases an in-flight projection.
  property var complete: null
  QmlTest {
    id: t
  }
  FileView {
    id: theme
    path: Qt.resolvedUrl('theme-shell.toml')
    blockLoading: true
    printErrors: false
  }
  Shared.DesktopFontSync {
    id: sync
    enabled: false
    family: 'Inter'
    bodyPixels: 12
    adapterPath: '/test/adapter'
    runner: function (argv, done) {
      root.calls = root.calls.concat([argv])
      root.complete = done
    }
  }
  Shared.DesktopFontSync {
    id: missing
    enabled: false
    family: 'Inter'
    bodyPixels: 12
    adapterPath: '/aranea-test/missing-font-helper'
  }
  Component.onCompleted: t.step(200, function () {
    Color.loadShell(theme.text())
    Style.fontBaseSize = 16
    t.equal(Style.font.body, 16, 'theme body text follows the shared base size')
    t.equal(Style.font.caption, 13, 'theme captions retain proportional scaling')
    t.equal(Style.font.title, 19, 'theme headings retain proportional scaling')
    t.equal(root.calls, [], 'inert host cannot change desktop fonts')
    sync.enabled = true
    sync.family = 'Source Sans 3'
    sync.bodyPixels = 16
    t.step(200, function () {
      t.equal(root.calls, [['/test/adapter', 'Source Sans 3', '16']], 'family and logical size coalesce into one projection')
      sync.bodyPixels = 20
      sync.family = 'IBM Plex Sans'
      t.step(200, function () {
        t.equal(root.calls.length, 1, 'running projection cannot overlap a newer one')
        root.complete(0)
        t.step(200, function () {
          t.equal(root.calls[1], ['/test/adapter', 'IBM Plex Sans', '20'], 'latest family and size apply after completion')
          root.complete(0)
          sync.invalidate()
          t.step(200, function () {
            t.equal(root.calls.length, 3, 'repeated text-size commands reproject an unchanged logical size')
            sync.bodyPixels = 24
            t.step(200, function () {
              root.complete(1)
              t.step(200, function () {
                t.equal(root.calls[3], ['/test/adapter', 'IBM Plex Sans', '24'], 'failed projection does not drop a newer queued size')
                root.complete(0)
                sync.enabled = false
                sync.bodyPixels = 28
                missing.enabled = true
                t.step(300, function () {
                  t.equal(root.calls.length, 4, 'disabled bridge cannot apply queued updates')
                  t.check(!missing.pending, 'failed process launch releases pending projection')
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  })
}
