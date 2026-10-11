// Actual editor validates fields, preserves literal argument rows and never launches.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as ProjectUi

ShellRoot {
  id: root
  // Capture the actual editor configuration request, without executing it.
  property var saved: null
  // Cancel is a local presentation event only.
  property int cancellations: 0
  QmlTest {
    id: t
  }
  ProjectUi.ProjectActionEditor {
    id: editor
    width: 360
    onSaveRequested: function (definition, revision) {
      root.saved = [definition, revision]
    }
    onCancelRequested: root.cancellations++
  }
  // Compare composited real text/background colors, rather than a theme token spelling.
  function luminance(color) {
    var linear = function (c) {
      return c <= 0.04045 ? c / 12.92 : Math.pow((c + 0.055) / 1.055, 2.4)
    }
    return 0.2126 * linear(color.r) + 0.7152 * linear(color.g) + 0.0722 * linear(color.b)
  }
  // Resolve alpha layers over the same dark surface as the real editor.
  function composite(foreground, background) {
    return Qt.rgba(foreground.r * foreground.a + background.r * (1 - foreground.a), foreground.g * foreground.a + background.g * (1 - foreground.a), foreground.b * foreground.a + background.b * (1 - foreground.a), 1)
  }
  // Require readable placeholder contrast for enabled and readonly argument fields.
  function placeholderReadable(field) {
    var background = composite(field.background.color, Color.background)
    var foreground = composite(field.placeholderTextColor, background)
    var a = luminance(foreground), b = luminance(background)
    console.log('EDITORPLACEHOLDER color=' + field.placeholderTextColor + ' contrast=' + ((Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05)))
    return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05) >= 4.5
  }
  Component.onCompleted: t.step(50, function () {
    t.check(typeof editor.useExample === 'function', 'action editor offers worked example drafts')
    if (typeof editor.useExample === 'function') {
      editor.begin(null, 4)
      editor.useExample('test')
      t.equal(editor.definition().argv, ['npm', 'test'], 'test example keeps individual literal arguments')
      t.equal(saved, null, 'choosing an example never saves or runs it')
      editor.useExample('dev')
      t.equal(editor.definition().argv, ['npm', 'test'], 'examples never overwrite an edited draft')
      editor.begin(null, 4)
      editor.useExample('dev')
      t.equal(editor.definition().kind, 'service', 'dev example uses a retained service')
      t.equal(editor.definition().argv, ['npm', 'run', 'dev'], 'dev example separates its arguments')
      var customFields = [['cwdRelative', 'apps/web'], ['timeoutSeconds', '90'], ['kind', 'service'], ['previewUrl', 'http://127.0.0.1:5173']]
      customFields.forEach(function (field) {
        editor.begin(null, 4)
        editor.setField(field[0], field[1])
        var before = editor.definition()
        editor.useExample('test')
        t.equal(editor.definition(), before, 'example preserves customized ' + field[0])
        t.equal(editor.draft[field[0]], field[1], 'example keeps exact draft value for ' + field[0])
      })
      editor.displayOnly = true
      editor.begin(null, 4)
      editor.useExample('test')
      t.equal(editor.draft.executable, '', 'capture refuses example draft mutation')
      editor.displayOnly = false
    }
    editor.begin(null, 4)
    editor.save()
    t.check(!saved && !!editor.fieldError, 'empty executable and name refuse locally')
    editor.setField('name', 'Run checks')
    editor.setField('executable', 'printf')
    editor.addArgument()
    t.check(placeholderReadable(t.findChild(editor, 'actionArgument:0')), 'enabled empty argument placeholder meets readable contrast; color=' + t.findChild(editor, 'actionArgument:0').placeholderTextColor)
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
    t.check(placeholderReadable(t.findChild(editor, 'actionArgument:0')), 'readonly capture argument placeholder stays readable; color=' + t.findChild(editor, 'actionArgument:0').placeholderTextColor)
    saved = null
    editor.save()
    t.check(!saved, 'capture editor refuses save')
    t.check(!!t.findChild(editor, 'actionExecutable'), 'actual executable field rendered')
    t.done()
  })
}
