// One section of the Aranea VPN dropdown (CONNECTED or AVAILABLE): a
// caption with the row count, then one NodeDeviceRow per VPN. A
// NetworkManager row carries a trailing FilamentSwitch, an own-app row an
// "open app" chip; both are settled by their row, so a click aimed at
// another row before a rebuild is ignored. A row's status (busy breathing,
// a failure urgent) replaces its type. Under a connected row sit its
// session details and traffic graph; under the row the prompt names, the
// shared credential prompt (read-only username, password, optional 2FA
// code). Pure view: plain inputs in, signals out.
//
// A row wrapper moving or resizing (a session line or graph appearing,
// the prompt opening or moving) reports layoutShifted, so the dropdown can
// settle clicks even when the section's own height stays the same.
//
// The Repeater's model is `rows` alone; status, sessions, graphs and the
// prompt are separate properties keyed by row key, so none of them ever
// rebuilds a delegate (or drops a half-typed password).
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // The caption, e.g. "CONNECTED".
  property string title: ""
  // Whether these rows are connected: rows are lit, switches on, and
  // session details and graphs show.
  property bool connected: false
  // Rows: [{key, kind ("nm" or "app"), name, glyph, label}], key being the
  // NetworkManager uuid or "app:" + the app's name.
  property var rows: []
  // Per-key action status: {key: {text, busy, failed}}.
  property var status: ({})
  // Per-key session details: {key: {ip, server, up}}.
  property var sessions: ({})
  // Per-key rate samples: {key: [{rx, tx}]}.
  property var graphs: ({})
  // The credential prompt: {key, username, password, code, busy, failed,
  // failedText}; key "" while closed.
  property var prompt: ({})
  // Showcase stand-in names in display order across both sections; empty
  // shows the real names.
  property var showcaseNames: []
  // How many rows earlier sections showed, for the showcase names.
  property int nameOffset: 0
  // The keyboard cursor's row, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a row
  // moving under a still pointer.
  property var pointerGate: null

  // Emitted when NetworkManager row INDEX or its switch is clicked.
  signal toggle(int index)
  // Emitted when own-app row INDEX or its chip is clicked.
  signal openApp(int index)
  // Emitted when the pointer moves onto row INDEX (through the gate).
  signal hovered(int index)
  // Emitted when a row wrapper moves or resizes without a rebuild.
  signal layoutShifted
  // Emitted on Enter in the prompt's last field.
  signal promptSubmit
  // Emitted when the prompt's connect button is clicked.
  signal promptConnect
  // Emitted on Esc in the prompt.
  signal promptCancel
  // Emitted when the password field's text changes to TEXT.
  signal passwordEdited(string text)
  // Emitted when the 2FA code field's text changes to TEXT.
  signal codeEdited(string text)

  // The status for KEY: {text, busy, failed}, empty when unknown.
  function statusOf(key) {
    var s = section.status ? section.status[key] : undefined
    return {
      text: s && s.text ? String(s.text) : "",
      busy: !!(s && s.busy),
      failed: !!(s && s.failed)
    }
  }

  // The session details for KEY: {ip, server, up}, "" when unknown.
  function sessionOf(key) {
    var s = section.sessions ? section.sessions[key] : undefined
    return {
      ip: s && s.ip ? String(s.ip) : "",
      server: s && s.server ? String(s.server) : "",
      up: s && s.up ? String(s.up) : ""
    }
  }

  // The rate samples for KEY, or [].
  function samplesOf(key) {
    var g = section.graphs ? section.graphs[key] : undefined
    return Array.isArray(g) ? g : []
  }

  // The name row INDEX shows: its NAME, or a showcase stand-in.
  function displayName(index, name) {
    var names = section.showcaseNames || []
    if (names.length === 0)
      return name
    var n = section.nameOffset + index
    return names[n] ? names[n] : "VPN " + (n + 1)
  }

  // The row wrapper at INDEX (objectName "vpnRowWrapper": the row, its
  // session and its prompt), or null when out of range; for ensureVisible.
  function rowWrapperAt(index) {
    return repeater.itemAt(index)
  }

  visible: section.rows.length > 0
  spacing: Style.space(6)

  Item {
    width: section.width
    implicitHeight: captionText.implicitHeight
    Text {
      id: captionText
      objectName: "sectionCaption"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: section.title
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      objectName: "sectionCount"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: String(section.rows.length)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }
  }
  Repeater {
    id: repeater
    model: section.rows
    Column {
      id: wrapper
      required property var modelData
      required property int index
      // Whether this is an own-app row.
      readonly property bool isApp: wrapper.modelData.kind === "app"
      // This row's action status.
      readonly property var rowStatus: section.statusOf(wrapper.modelData.key)
      // Whether the prompt is open for this row.
      readonly property bool promptOpen: !!section.prompt && !!section.prompt.key && section.prompt.key === wrapper.modelData.key
      // The indent of the details under the row (past its node and glyph).
      readonly property real indent: Style.space(24)

      objectName: "vpnRowWrapper"
      width: section.width
      spacing: Style.space(4)
      onYChanged: section.layoutShifted()
      onHeightChanged: section.layoutShifted()

      Aranea.NodeDeviceRow {
        id: vpnRow
        objectName: "vpnRow"
        width: wrapper.width
        glyph: wrapper.modelData.glyph || ""
        label: section.displayName(wrapper.index, wrapper.modelData.name || "")
        // The prompt carries its own message while open.
        detail: wrapper.promptOpen ? "" : (wrapper.rowStatus.text || wrapper.modelData.label || "")
        detailColor: wrapper.rowStatus.failed ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        active: section.connected
        // A connected VPN carries the selected highlight.
        selected: active
        busy: wrapper.rowStatus.busy
        hasCursor: section.cursorIndex === wrapper.index
        pointerGate: section.pointerGate
        onChosen: wrapper.isApp ? section.openApp(wrapper.index) : section.toggle(wrapper.index)
        onEntered: section.hovered(wrapper.index)

        // The trailing slot's only child, so the slot sizes to it.
        Item {
          width: wrapper.isApp ? chip.width : vpnSwitch.width
          height: wrapper.isApp ? chip.height : vpnSwitch.height

          Aranea.FilamentSwitch {
            id: vpnSwitch
            objectName: wrapper.isApp ? "" : "vpnSwitch"
            visible: !wrapper.isApp
            anchors.verticalCenter: parent.verticalCenter
            // A re-sort can rebuild this row under a still pointer: the
            // row's settle guard covers its switch too.
            clickGate: vpnRow
            // The row's own hover fill covers the switch.
            ownHover: false
            pointerGate: section.pointerGate
            checked: section.connected
            onToggled: section.toggle(wrapper.index)
          }
          Aranea.FilamentPill {
            id: chip
            objectName: wrapper.isApp ? "openAppChip" : ""
            visible: wrapper.isApp
            anchors.verticalCenter: parent.verticalCenter
            text: "open app"
            tooltipText: "Open the app to sign in"
            clickGate: vpnRow
            onClicked: section.openApp(wrapper.index)
          }
        }
      }
      VpnSession {
        id: sessionView
        x: wrapper.indent
        width: wrapper.width - wrapper.indent
        // Only connected rows have a session; an available row's leftover
        // details never show.
        visible: section.connected && (sessionView.ip !== "" || sessionView.server !== "" || sessionView.up !== "" || sessionView.samples.length > 0)
        ip: section.sessionOf(wrapper.modelData.key).ip
        server: section.sessionOf(wrapper.modelData.key).server
        up: section.sessionOf(wrapper.modelData.key).up
        samples: section.connected ? section.samplesOf(wrapper.modelData.key) : []
      }
      Aranea.CredentialPrompt {
        x: wrapper.indent
        width: wrapper.width - wrapper.indent
        visible: wrapper.promptOpen
        pointerGate: section.pointerGate
        fields: [
          {
            key: "username",
            label: "Username",
            placeholder: "No username in this profile",
            readOnly: true,
            value: wrapper.promptOpen ? (section.prompt.username || "") : ""
          },
          {
            key: "password",
            label: "Password",
            placeholder: "Password",
            secret: true,
            value: wrapper.promptOpen ? (section.prompt.password || "") : ""
          },
          {
            key: "code",
            label: "2FA code",
            placeholder: "2FA code (optional)",
            optional: true,
            value: wrapper.promptOpen ? (section.prompt.code || "") : ""
          }
        ]
        busy: wrapper.promptOpen && !!section.prompt.busy
        busyText: wrapper.rowStatus.text || "Connecting…"
        failed: wrapper.promptOpen && !!section.prompt.failed
        failedText: wrapper.promptOpen && section.prompt.failedText ? section.prompt.failedText : "Couldn't connect"
        onSubmit: section.promptSubmit()
        onCancel: section.promptCancel()
        onConnectClicked: section.promptConnect()
        onEdited: function (key, text) {
          if (key === "password")
            section.passwordEdited(text)
          else if (key === "code")
            section.codeEdited(text)
        }
      }
    }
  }
}
