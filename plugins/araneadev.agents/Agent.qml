// Aranea Agents (araneadev.agents, cloned from omarchy.agents): the
// per-agent usage record watcher. Stock's logic stays unchanged (reading
// the usage file through FileView and reparsing it on every change).
import QtQuick
import Quickshell.Io

// One agent's usage record, read straight off the data file that
// omarchy-agent-usage-update maintains. The panel never learns how the
// numbers were made: a record that appears in the usage directory is an
// agent, whoever wrote it.
Item {
  id: root
  visible: false

  // The provider id this record belongs to (claude, codex, fireworks).
  property string agentId: ""
  // The usage file this watcher reads and reparses on change.
  property string path: ""
  // The parsed usage record, or null while unset or unparsable.
  property var record: null

  FileView {
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.record = null
  }

  // Parses the raw file content into root.record, or null on bad JSON.
  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.record = parsed && typeof parsed === "object" ? parsed : null
    } catch (e) {
      console.warn("agents", "Ignoring bad usage record", root.path, e)
      root.record = null
    }
  }
}
