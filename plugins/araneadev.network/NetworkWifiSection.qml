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
// rebuilds a delegate (and never drops a half-typed passphrase).
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
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
  // Emitted on Enter in the passphrase or the connect button.
  signal promptSubmit
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
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
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

      Text {
        objectName: "wifiTitle"
        visible: (wrapper.modelData.title || "") !== ""
        text: wrapper.modelData.title || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
      Aranea.NodeDeviceRow {
        id: wifiRow
        objectName: "wifiRow"
        width: wrapper.width
        glyph: wrapper.modelData.glyph || ""
        label: wrapper.modelData.label || "Hidden"
        // Stock hides the status while the prompt is open for the row.
        detail: wrapper.promptOpen ? "" : wrapper.rowStatus.text
        detailColor: wrapper.rowStatus.failed ? Aranea.DesignTokens.urgent : Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        active: !!wrapper.modelData.connected
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
            color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
          NetworkForgetButton {
            id: forgetBtn
            anchors.verticalCenter: parent.verticalCenter
            forgettable: !!wrapper.modelData.forgettable
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
      // Stock's inline prompt, framed by a thin accent-to-violet strand.
      Item {
        id: promptPanel
        objectName: "promptPanel"
        visible: wrapper.promptOpen
        width: wrapper.width
        height: visible ? promptContent.implicitHeight + Style.space(16) : 0

        Rectangle {
          anchors.top: parent.top
          width: parent.width
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
              position: 0
              color: Aranea.DesignTokens.accent
            }
            GradientStop {
              position: 1
              color: Aranea.DesignTokens.strandEnd
            }
          }
        }
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: 1
          gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
              position: 0
              color: Aranea.DesignTokens.accent
            }
            GradientStop {
              position: 1
              color: Aranea.DesignTokens.strandEnd
            }
          }
        }
        Rectangle {
          anchors.left: parent.left
          width: 1
          height: parent.height
          color: Aranea.DesignTokens.accent
        }
        Rectangle {
          anchors.right: parent.right
          width: 1
          height: parent.height
          color: Aranea.DesignTokens.strandEnd
        }
        Column {
          id: promptContent
          x: Style.space(8)
          y: Style.space(8)
          width: parent.width - Style.space(16)
          spacing: Style.space(4)

          TextField {
            id: identityField
            objectName: "identityField"
            width: promptContent.width - connectButton.width - Style.space(6)
            visible: wrapper.enterprise && !wrapper.promptMessage
            placeholderText: "Identity (user@domain)"
            foreground: Aranea.DesignTokens.foreground
            accent: Aranea.DesignTokens.accent
            horizontalPadding: Style.spacing.controlGap
            verticalPadding: Style.spacing.controlPaddingY
            text: wrapper.promptOpen ? (section.prompt.identity || "") : ""
            onAccepted: passphraseField.forceActiveFocus()
            onTextChanged: if (wrapper.promptOpen && text !== (section.prompt.identity || ""))
              section.identityEdited(text)
            Keys.onEscapePressed: section.promptCancel()
            onVisibleChanged: if (visible)
              Qt.callLater(identityField.forceActiveFocus)
            Component.onCompleted: if (visible)
              Qt.callLater(identityField.forceActiveFocus)
          }
          Item {
            width: promptContent.width
            height: Math.max(passphraseField.visible ? passphraseField.implicitHeight : 0, connectButton.visible ? connectButton.implicitHeight : 0, promptStatus.visible ? promptStatus.implicitHeight : 0)

            TextField {
              id: passphraseField
              objectName: "passphraseField"
              anchors.left: parent.left
              anchors.right: connectButton.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              visible: !wrapper.promptMessage
              password: true
              placeholderText: "Passphrase"
              foreground: Aranea.DesignTokens.foreground
              accent: Aranea.DesignTokens.accent
              horizontalPadding: Style.spacing.controlGap
              verticalPadding: Style.spacing.controlPaddingY
              text: wrapper.promptOpen ? (section.prompt.passphrase || "") : ""
              onAccepted: section.promptSubmit()
              onTextChanged: if (wrapper.promptOpen && text !== (section.prompt.passphrase || ""))
                section.passphraseEdited(text)
              Keys.onEscapePressed: section.promptCancel()
              onVisibleChanged: if (visible && !wrapper.enterprise)
                Qt.callLater(passphraseField.forceActiveFocus)
              Component.onCompleted: if (visible && !wrapper.enterprise)
                Qt.callLater(passphraseField.forceActiveFocus)
            }
            Text {
              id: promptStatus
              objectName: "promptStatus"
              anchors.fill: parent
              visible: wrapper.promptMessage
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              text: wrapper.promptOpen && section.prompt.failed ? "Wrong password" : "Connecting..."
              color: wrapper.promptOpen && section.prompt.failed ? Aranea.DesignTokens.urgent : Aranea.DesignTokens.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }
            PanelActionButton {
              id: connectButton
              objectName: "connectButton"
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              visible: !wrapper.promptMessage
              enabled: passphraseField.text.length > 0 && (!wrapper.enterprise || identityField.text.length > 0)
              iconText: String.fromCodePoint(0xf012c)
              tooltipText: "Connect"
              foreground: Aranea.DesignTokens.foreground
              hoverColor: Aranea.DesignTokens.accent
              onClicked: section.promptSubmit()
            }
          }
        }
      }
    }
  }
}
