// Behaviour of the clipboard plugin's non-visual entry (Clipboard.qml) with
// its window switched off: secrets never reach the editor, rapid saves keep
// the newest history and pastes wait for them, opening expires old secrets,
// marking a secret restamps it, colour rows carry a Qt swatch.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.clipboard" as Clip

ShellRoot {
  id: shell

  // Commands the plugin tried to run (argv arrays), newest last.
  property var ran: []
  // Time the test started, in ms; fixture timestamps are relative to it.
  readonly property real now: Date.now()

  QmlTest {
    id: t
  }

  Clip.Clipboard {
    id: clip
    windowEnabled: false
    captureEnabled: false
    omarchyPath: "/opt/omarchy"
    historyPath: Quickshell.env("HOME") + "/clipboard-history.json"
    run: function (argv) {
      shell.ran = shell.ran.concat([argv])
    }
  }

  // Index in the display rows of the entry whose text or title matches.
  function rowIndex(match) {
    for (var i = 0; i < clip.displayModel.count; i++) {
      var row = clip.displayModel.get(i)
      if (row.fullText === match || row.title === match)
        return i
    }
    return -1
  }

  // Commands whose program ends with NAME.
  function ranNamed(name) {
    return shell.ran.filter(function (argv) {
      return String(argv[0]).slice(-name.length) === name
    })
  }

  Component.onCompleted: {
    var old = shell.now - 3600000
    clip.loadHistory(JSON.stringify([
      {
        type: "text",
        text: "plain words here",
        capturedAtMs: shell.now
      },
      {
        type: "text",
        text: "x7Kp2mQ9vL4nR8sT",
        capturedAtMs: shell.now,
        secret: true
      },
      {
        type: "text",
        text: "#11223380",
        capturedAtMs: shell.now
      },
      {
        type: "text",
        text: "Qk3xZp9vL2mX7nR4",
        capturedAtMs: old,
        secret: true
      },
      {
        type: "text",
        text: "old note",
        capturedAtMs: old
      }
    ]))
    clip.open("{}")
    t.check(clip.opened, "open shows the picker")
    t.equal(rowIndex("Qk3xZp9vL2mX7nR4"), -1, "opening expires an old secret")

    // Alt+Enter on a secret: refused with a notice, nothing written or run.
    var secret = -1
    for (var i = 0; i < clip.displayModel.count; i++)
      if (clip.displayModel.get(i).secret)
        secret = i
    t.check(secret >= 0, "fixture has a live secret")
    clip.openIndex(secret)
    t.equal(clip.notice, "SECRETS CAN'T BE OPENED IN THE EDITOR", "secret open refused with a notice")
    t.equal(ranNamed("omarchy-clipboard-open").length, 0, "no open command for a secret")

    // Colour rows carry the Qt colour.
    var colour = rowIndex("#11223380")
    t.equal(colour >= 0 ? clip.displayModel.get(colour).swatch : "", "#80112233", "swatch in Qt order")

    // Ctrl+S on an old plain row restamps it.
    clip.toggleSecretIndex(rowIndex("old note"))
    var marked = clip.history.filter(function (e) {
      return e.text === "old note"
    })[0]
    t.check(marked.secret && marked.capturedAtMs >= shell.now, "marking a secret restamps it")

    // Two quick deletes, then a paste: it waits for both writes.
    clip.open("{}")
    clip.removeDisplayIndex(0)
    clip.removeDisplayIndex(0)
    t.check(clip.pendingSaves > 0, "saves are pending")
    clip.activateIndex(0)
    t.equal(ranNamed("omarchy-clipboard-paste-text").length, 0, "paste waits for the writes")
    t.step(1500, function () {
      t.equal(clip.pendingSaves, 0, "writes finished")
      t.equal(ranNamed("omarchy-clipboard-paste-text").length, 1, "paste ran after the writes")
      t.equal(clip.history.length, 2, "history keeps the newest state")
      t.done()
    })
  }
}
