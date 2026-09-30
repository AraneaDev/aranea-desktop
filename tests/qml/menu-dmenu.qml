// Behaviour of a dmenu request (MenuDmenu.qml): begin() reads the payload,
// rowsFor() splits "glyph\tlabel\tsubtext" options and filters on label and
// subtext, finish() writes the answer and touches the done file, and a
// finish without a pending request reports false.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: shell

  // How often a result write finished.
  property int finishes: 0
  // Scratch directory for the result files.
  readonly property string dir: Quickshell.env("TMPDIR")

  QmlTest {
    id: t
  }

  Menu.MenuDmenu {
    id: dmenu
    onFinished: shell.finishes += 1
  }

  // Reads the selection file once the answer is written.
  FileView {
    id: selectionView
    path: shell.dir + "/dmenu-selection"
    blockLoading: true
    printErrors: false
  }

  Component.onCompleted: {
    t.equal(dmenu.finish("x"), false, "no pending request, nothing to answer")
    var mode = dmenu.begin({
      mode: "select",
      prompt: "Pick",
      options: ["Alpha", "*\tBeta\tsecond", "Gamma"],
      selectionFile: shell.dir + "/dmenu-selection",
      doneFile: shell.dir + "/dmenu-done",
      width: 500,
      maxHeight: 200
    })
    t.equal(mode, "select", "select mode")
    t.equal(dmenu.prompt, "Pick", "the prompt")
    t.equal(dmenu.requestedWidth, 500, "the width")
    t.equal(dmenu.requestedMaxHeight, 200, "the height cap")
    t.equal(dmenu.requestActive, true, "a done file makes it pending")
    t.equal(dmenu.rowsFor("").length, 3, "every option is a row")
    var beta = dmenu.rowsFor("second")
    t.equal(beta.length, 1, "the filter matches subtext")
    t.equal(beta[0].icon, "*", "the glyph becomes the icon")
    t.equal(beta[0].label, "Beta", "the label")
    t.equal(beta[0].detail, "second", "the subtext")
    t.equal(beta[0].itemId, "dmenu.1", "ids follow the option index")
    t.equal(dmenu.rowsFor("gam")[0].label, "Gamma", "the filter matches labels, ignoring case")
    t.equal(dmenu.begin({
      mode: "input"
    }), "input", "input mode")
    t.equal(dmenu.prompt, "Input", "input's default prompt")
    dmenu.begin({
      mode: "select",
      options: ["Alpha"],
      selectionFile: shell.dir + "/dmenu-selection",
      doneFile: shell.dir + "/dmenu-done"
    })
    t.equal(dmenu.finish("Beta\tsecond"), true, "a pending request is answered")
    t.equal(dmenu.requestActive, false, "and is no longer pending")
    t.waitFor(function () {
      return shell.finishes === 1
    }, 10000, "the answer is written", function () {
      selectionView.reload()
      t.equal(selectionView.text(), "Beta\tsecond\n", "the selection file holds the answer")
      t.done()
    })
  }
}
