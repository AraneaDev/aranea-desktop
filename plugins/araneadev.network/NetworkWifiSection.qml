// The Wi-Fi list of the Aranea Network dropdown: "SCANNING WI-FI…" while
// a scan runs, then one NodeDeviceRow per network with stock's "KNOWN
// NETWORKS" / "OTHER NETWORKS" titles above the rows that start them, a
// lock on secured rows, a forget button on forgettable ones, and stock's
// inline passphrase prompt (identity first for enterprise) under the row
// it was opened for. Hidden without a Wi-Fi station. Pure view: plain
// inputs in, signals out.
//
// The Repeater's model is `rows` alone; status and the prompt are separate
// properties keyed by SSID, so a status change or a keystroke never
// rebuilds a delegate (and never drops a half-typed passphrase). A row
// wrapper moving or resizing without a rebuild (the prompt opening, moving
// or turning into its message, the scanning caption) reports
// layoutShifted, so the dropdown can settle clicks.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: section

  // Wi-Fi rows: [{key, label, glyph, title, secured, known, connected,
  // forgettable, enterprise}], key being the SSID ("" for a hidden one).
  property var rows: []
  // Per-SSID action status: {ssid: {text, failed, busy}}.
  property var status: ({})
  // The passphrase prompt: {ssid, enterprise, busy, failed, passphrase,
  // identity}; ssid "" while closed.
  property var prompt: ({})
  // Whether a Wi-Fi scan is running.
  property bool scanning: false
  // Whether there's a Wi-Fi station at all; the section hides without one.
  property bool available: true
  // Whether a Wi-Fi action is running: rows dim and can't be chosen, and
  // forget hides, as stock's rows were disabled.
  property bool disabled: false
  // The keyboard cursor's row, or -1 when the cursor isn't here.
  property int cursorIndex: -1
  // Whether the keyboard cursor sits on the cursor row's forget action.
  property bool cursorAction: false
  // Optional PointerMoveGate (qs.Ui) filtering synthetic hover from a row
  // moving under a still pointer.
  property var pointerGate: null

  // Emitted when row INDEX is clicked.
  signal primary(int index)
  // Emitted when row INDEX's forget button is clicked.
  signal forget(int index)
  // Emitted when the pointer moves onto row INDEX (ACTION false) or its
  // forget button (ACTION true), through the gate.
  signal hovered(int index, bool action)
  // Emitted when the pointer leaves row INDEX's forget button.
  signal actionLeft(int index)
  // Emitted when a row wrapper moves or resizes without a rebuild.
  signal layoutShifted
  // Emitted on Enter in the passphrase.
  signal promptSubmit
  // Emitted when the prompt's connect button is clicked.
  signal promptConnect
  // Emitted on Esc in either prompt field.
  signal promptCancel
  // Emitted when the passphrase field's text changes to TEXT.
  signal passphraseEdited(string text)
  // Emitted when the identity field's text changes to TEXT.
  signal identityEdited(string text)

  // The status for SSID: {text, failed, busy}, empty when unknown.
  function statusOf(ssid) {
    var s = section.status ? section.status[ssid] : undefined
    return {
      text: s && s.text ? String(s.text) : "",
      failed: !!(s && s.failed),
      busy: !!(s && s.busy)
    }
  }

  // The row wrapper at INDEX (objectName "wifiRowWrapper": the title line,
  // the row and its prompt), or null when out of range; for ensureVisible.
  function rowWrapperAt(index) {
    return repeater.itemAt(index)
  }

  objectName: "wifiSection"
  visible: section.available
  spacing: Style.space(6)

  Text {
    objectName: "scanningCaption"
    visible: section.scanning
    text: "SCANNING WI-FI…"
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 0
  }
  Repeater {
    id: repeater
    model: section.rows
    Column {
      id: wrapper
      required property var modelData
      required property int index
      // This row's action status.
      readonly property var rowStatus: section.statusOf(wrapper.modelData.key)
      // Whether the prompt is open for this row.
      readonly property bool promptOpen: !!section.prompt && !!section.prompt.ssid && section.prompt.ssid === wrapper.modelData.key
      // Whether this row's prompt is an enterprise one.
      readonly property bool enterprise: wrapper.promptOpen && !!section.prompt.enterprise
      // Whether the prompt shows a message instead of its fields.
      readonly property bool promptMessage: wrapper.promptOpen && (!!section.prompt.busy || !!section.prompt.failed)
      // Whether the keyboard cursor is on this row.
      readonly property bool hasCursor: section.cursorIndex === wrapper.index

      objectName: "wifiRowWrapper"
      width: section.width
      spacing: Style.space(4)
      onYChanged: section.layoutShifted()
      onHeightChanged: section.layoutShifted()

      Text {
        objectName: "wifiTitle"
        visible: (wrapper.modelData.title || "") !== ""
        text: wrapper.modelData.title || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 0
      }
      Aranea.NodeDeviceRow {
        id: wifiRow
        refined: true
        objectName: "wifiRow"
        width: wrapper.width
        glyph: wrapper.modelData.glyph || ""
        label: wrapper.modelData.label || "Hidden"
        // Stock hides the status while the prompt is open for the row.
        detail: wrapper.promptOpen ? "" : wrapper.rowStatus.text
        detailColor: wrapper.rowStatus.failed ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
        active: !!wrapper.modelData.connected
        // The connected network carries the selected highlight.
        selected: active
        available: !section.disabled
        busy: wrapper.rowStatus.busy
        signal: -1
        hasCursor: wrapper.hasCursor
        pointerGate: section.pointerGate
        onChosen: section.primary(wrapper.index)
        onEntered: section.hovered(wrapper.index, false)

        // The trailing slot's only child, so the slot sizes to it; a Row
        // leaves its hidden children out of its own size.
        Row {
          spacing: Style.space(6)
          Text {
            objectName: "wifiLock"
            anchors.verticalCenter: parent.verticalCenter
            // Forget takes the lock's place, as stock does.
            visible: !!wrapper.modelData.secured && !forgetBtn.shown
            text: String.fromCodePoint(0xf033e)
            color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
            font.family: Aranea.Typography.iconFamily
            font.pixelSize: Style.font.caption
          }
          Aranea.ForgetButton {
            id: forgetBtn
            anchors.verticalCenter: parent.verticalCenter
            tooltipText: "Forget network"
            forgettable: !!wrapper.modelData.forgettable && !section.disabled
            rowHovered: wifiRow.hovered
            hasCursor: wrapper.hasCursor
            cursorAction: section.cursorAction
            pointerGate: section.pointerGate
            onClicked: section.forget(wrapper.index)
            onPointerEntered: section.hovered(wrapper.index, true)
            onPointerLeft: section.actionLeft(wrapper.index)
          }
        }
      }
      // Stock's inline prompt (identity first for enterprise), framed by a
      // thin accent-to-violet strand.
      Aranea.CredentialPrompt {
        objectName: "promptPanel"
        visible: wrapper.promptOpen
        width: wrapper.width
        // Settles the connect button like the rows: not within 300 ms of
        // opening or of a layout shift, unless the pointer moved there.
        pointerGate: section.pointerGate
        fields: [
          {
            key: "identity",
            label: "Identity",
            placeholder: "Identity (user@domain)",
            hidden: !wrapper.enterprise,
            value: wrapper.promptOpen ? (section.prompt.identity || "") : ""
          },
          {
            key: "passphrase",
            label: "Passphrase",
            placeholder: "Passphrase",
            secret: true,
            value: wrapper.promptOpen ? (section.prompt.passphrase || "") : ""
          }
        ]
        busy: wrapper.promptOpen && !!section.prompt.busy
        busyText: "Connecting..."
        failed: wrapper.promptOpen && !!section.prompt.failed
        failedText: "Wrong password"
        onSubmit: section.promptSubmit()
        onCancel: section.promptCancel()
        onConnectClicked: section.promptConnect()
        onEdited: function (key, text) {
          if (key === "identity")
            section.identityEdited(text)
          else
            section.passphraseEdited(text)
        }
      }
    }
  }
}
