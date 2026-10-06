// Real config-file creation/replacement updates consumers without changing glyphs.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.shared" as Shared
import "plugins/araneadev.settings" as Settings
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: root
  // Dedicated glyph font observed before any text preference mutation.
  property string originalIconFamily: Shared.Typography.iconFamily
  QmlTest {
    id: t
  }
  Menu.MenuStyle {
    id: menuStyle
  }
  Settings.SettingsLabel {
    id: label
    text: 'Interface'
  }
  Settings.SettingsLabel {
    id: value
    technical: true
    text: '2.667'
  }
  FileView {
    id: probe
    path: Shared.RuntimePaths.fontsConfigPath
    blockLoading: true
    printErrors: false
  }
  Settings.SettingsController {
    id: controller
    runner: function (argv, done) {
      var fonts = JSON.parse(probe.text())
      fonts.availability = 'available'
      done(0, JSON.stringify({
        schemaVersion: 1,
        ok: true,
        state: {
          fonts: fonts
        },
        error: null
      }), '')
    }
  }
  Process {
    id: writer
    command: ['python3', '-c', 'import pathlib,sys; p=pathlib.Path(sys.argv[1]); p.parent.mkdir(parents=True,exist_ok=True); q=p.with_suffix(".next"); q.write_text(sys.argv[2]); q.replace(p)', Shared.RuntimePaths.fontsConfigPath, '{"uiFamily":"Liberation Sans","technicalFamily":"Liberation Mono"}']
    onExited: {
      probe.reload()
      controller.refresh()
      t.waitFor(function () {
        return label.font.family === 'Liberation Sans' && value.font.family === 'Liberation Mono'
      }, 3000, 'first save and owner readback update interface and technical consumers', function () {
        t.equal(menuStyle.fontFamily, Quickshell.env('OMARCHY_MENU_FONT') || 'Liberation Sans', 'launcher-specific font override retains precedence')
        t.equal(Shared.Typography.iconFamily, root.originalIconFamily, 'text preferences preserve dedicated icon family')
        fallback.running = true
      })
    }
  }
  Process {
    id: fallback
    command: ['python3', '-c', 'import pathlib,sys; pathlib.Path(sys.argv[1]).write_text("invalid json")', Shared.RuntimePaths.fontsConfigPath]
    onExited: t.waitFor(function () {
      return Shared.Typography.preferences.uiFamily === undefined
    }, 3000, 'malformed replacement falls back to defaults', function () {
      t.equal(label.font.family, 'sans-serif', 'invalid preferences retain readable UI default')
      t.done()
    })
  }
  Component.onCompleted: t.step(50, function () {
    writer.running = true
  })
}
