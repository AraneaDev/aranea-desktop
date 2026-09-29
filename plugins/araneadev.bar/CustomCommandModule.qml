// Configurable command-backed bar widget.
// qmllint disable missing-property unqualified
import Quickshell.Io
import QtQuick
import qs.Commons
import qs.Ui

WidgetButton {
  id: customRoot

  // Public contract member.
  property var owner: null
  // Public contract member.
  required property var entry
  // Canonical module identity derived from the configured entry.
  readonly property string moduleName: owner && typeof owner.entryId === "function" ? owner.entryId(entry) : String(entry && entry.id || "")
  // Settings object supplied by the bar owner for this entry.
  readonly property var settings: owner && typeof owner.entrySettings === "function" ? owner.entrySettings(entry) : ({})
  // Last command output rendered by the widget.
  property string outputText: ""
  // Last tooltip text returned by the command.
  property string outputTooltip: ""
  // Whether the command reported an active state.
  property bool outputActive: false

  // Reads an entry setting, falling back when it is absent.
  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // Parses command output into the widget's display state.
  function update(raw) {
    var data = Util.parseModuleJson(raw)
    var klass = data.class || data.alt || ""

    outputText = data.text || String(raw || "").trim()
    outputTooltip = data.tooltip || String(setting("tooltip", ""))
    outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
  }

  bar: owner
  text: outputText || String(setting("text", ""))
  tooltipText: outputTooltip || String(setting("tooltip", ""))
  active: outputActive
  keepSpace: setting("keepSpace", false) === true
  horizontalMargin: Number(setting("horizontalMargin", 7.5))
  verticalPadding: Number(setting("verticalPadding", 6))
  fontSize: Number(setting("fontSize", 12))

  onPressed: function (button) {
    var command = ""
    if (button === Qt.RightButton)
      command = String(setting("onRightClick", ""))
    else if (button === Qt.MiddleButton)
      command = String(setting("onMiddleClick", ""))
    else
      command = String(setting("onClick", ""))

    if (command && owner)
      owner.run(command)
  }

  Process {
    id: customProc
    command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: customRoot.update(text)
    }
  }

  Timer {
    interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
    running: String(customRoot.setting("exec", "")) !== ""
    repeat: true
    triggeredOnStart: true
    onTriggered: if (customRoot.owner)
      customRoot.owner.runProcess(customProc)
  }
}
