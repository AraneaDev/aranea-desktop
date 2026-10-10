// Actual editor validates fields, preserves literal argument rows and never launches.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Capture the actual editor configuration request, without executing it.
  property var saved: null
  // Cancel is a local presentation event only.
  property int cancellations: 0
  QmlTest {
    id: t
  }
  Settings.ProjectActionEditor {
    id: editor
    width: 360
    onSaveRequested: function (definition, revision) {
      root.saved = [definition, revision]
    }
    onCancelRequested: root.cancellations++
  }
  Component.onCompleted: t.step(50, function () {
    editor.begin(null, 4)
    editor.save()
    t.check(!saved && !!editor.fieldError, 'empty executable and name refuse locally')
    editor.setField('name', 'Run checks')
    editor.setField('executable', 'printf')
    editor.addArgument()
    editor.setArgument(0, 'a $HOME ; <b>literal</b>')
    editor.addArgument()
    t.equal(editor.definition().argv, ['printf', 'a $HOME ; <b>literal</b>', ''], 'literal and later empty argument are retained')
    editor.removeArgument(0)
    editor.save()
    t.equal(saved[0].argv, ['printf', ''], 'save emits configured argv without parsing')
    t.equal(saved[1], 4, 'save retains edit store revision')
    editor.setField('kind', 'service')
    editor.setField('previewUrl', 'https://example.com:3000')
    saved = null
    editor.save()
    t.check(!saved, 'non-loopback preview refuses')
    editor.setField('previewUrl', 'http://[::1]:3000/path')
    editor.save()
    t.equal(saved[0].timeoutSeconds, null, 'service has no command timeout')
    editor.setField('cwdRelative', '../outside')
    t.check(!!editor.validate(), 'cwd escape refuses')
    editor.setField('cwdRelative', 'nested//folder')
    t.check(!!editor.validate(), 'empty cwd path segment refuses like store')
    editor.setField('cwdRelative', '.')
    editor.setField('previewUrl', 'http://127.0.0.1:3000/has space')
    t.check(!!editor.validate(), 'URL whitespace refuses like store')
    editor.cancel()
    t.equal(cancellations, 1, 'Cancel only emits cancellation')
    editor.displayOnly = true
    saved = null
    editor.save()
    t.check(!saved, 'capture editor refuses save')
    t.check(!!t.findChild(editor, 'actionExecutable'), 'actual executable field rendered')
    t.done()
  })
}
