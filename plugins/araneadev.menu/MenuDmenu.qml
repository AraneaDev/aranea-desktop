// A dmenu-style request served by the Aranea menu (MenuDmenu): Omarchy's
// select and input pickers send a prompt, options and result files; this
// holds the request, turns options into rows, and writes the answer. Menu.qml
// owns one as `dmenu`.
import Quickshell.Io
import QtQuick
import qs.Commons

Item {
  id: dmenu

  // Prompt text shown in the header.
  property string prompt: ""
  // Raw option strings ("label", "glyph\tlabel" or "glyph\tlabel\tsubtext").
  property var options: []
  // File the answer is written to.
  property string selectionFile: ""
  // File touched when the request finishes (answered or cancelled).
  property string doneFile: ""
  // Requested card width, in unscaled units.
  property int requestedWidth: 300
  // Requested row-list height cap, in unscaled units (0 for none).
  property int requestedMaxHeight: 0
  // Whether the request is still waiting for its answer.
  property bool requestActive: false

  // Emitted when the answer (or cancellation) has been written.
  signal finished

  // Takes a request from PAYLOAD and returns its mode ("select" or "input").
  function begin(payload: var): string {
    var mode = payload.mode === "input" ? "input" : "select"
    dmenu.prompt = String(payload.prompt || (mode === "input" ? "Input" : "Select"))
    dmenu.options = Array.isArray(payload.options) ? payload.options : []
    dmenu.selectionFile = String(payload.selectionFile || "")
    dmenu.doneFile = String(payload.doneFile || "")
    dmenu.requestActive = !!dmenu.doneFile
    dmenu.requestedWidth = Math.max(1, Number(payload.width || 300))
    dmenu.requestedMaxHeight = Math.max(0, Number(payload.maxHeight || 0))
    return mode
  }

  // Forgets the request (the command menu opened instead).
  function reset(): void {
    dmenu.requestActive = false
    dmenu.selectionFile = ""
    dmenu.doneFile = ""
  }

  // The option rows matching FILTER (label or subtext, ignoring case).
  function rowsFor(filter: string): var {
    var query = String(filter || "").trim().toLowerCase()
    var rows = []
    for (var i = 0; i < dmenu.options.length; i++) {
      // An option is "<label>", "<glyph>\t<label>", or
      // "<glyph>\t<label>\t<subtext>". The glyph never comes back with the
      // selection; the subtext renders under the label, filters alongside it,
      // and returns with the selection as a stable key for same-named rows.
      var parts = String(dmenu.options[i] || "").split("\t")
      var icon = parts.length > 1 ? parts.shift() : ""
      var label = parts.shift() || ""
      var detail = parts.join("\t")
      if (query && label.toLowerCase().indexOf(query) < 0 && detail.toLowerCase().indexOf(query) < 0)
        continue
      rows.push({
        itemId: "dmenu." + i,
        kind: "dmenu",
        icon: icon,
        iconFont: "",
        appIcon: "",
        appId: "",
        label: label,
        target: "",
        detail: detail,
        path: "",
        childCount: 0,
        action: "",
        provider: "",
        score: i,
        section: ""
      })
    }
    return rows
  }

  // Answers the pending request: writes SELECTION (unless null) and touches the done file. Returns false when none is pending.
  function finish(selection: var): bool {
    if (!dmenu.requestActive || !dmenu.doneFile)
      return false
    var activeSelectionFile = dmenu.selectionFile
    var activeDoneFile = dmenu.doneFile
    dmenu.reset()
    if (selection === null || selection === undefined)
      resultProc.command = ["bash", "-c", ": > " + Util.shellQuote(activeDoneFile)]
    else
      resultProc.command = ["bash", "-c", "printf '%s\\n' " + Util.shellQuote(selection) + " > " + Util.shellQuote(activeSelectionFile) + "; : > " + Util.shellQuote(activeDoneFile)]
    resultProc.running = true
    return true
  }

  // Writes the answer files.
  Process {
    id: resultProc
    onExited: dmenu.finished()
  }
}
