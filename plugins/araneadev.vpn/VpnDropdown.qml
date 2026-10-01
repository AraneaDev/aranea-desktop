// The Aranea VPN dropdown's view: the header, the pinned CONNECTED section
// (each row with its session details and traffic graph), then AVAILABLE
// in a Flickable (objectName "vpnScroll") capped at maxScrollHeight, the
// empty text and the key hint. Drawn from one plain view object
// (Panel.vpnView) plus fast-changing properties kept out of it (status,
// sessions, graphs, the prompt), and reporting every user action through a
// single action signal. No NetworkManager objects and no nmcli logic here:
// the view gets ready strings, so tests drive it with fixtures.
//
// Anything that moves rows under a still pointer without rebuilding them
// (a session growing its IP, Server and graph lines, the prompt opening, a
// scroll) stamps layoutChangedAt, which the rows, switches, chips and the
// prompt's connect button read through pointerGate: a click within 300 ms
// of it is ignored unless the pointer has really moved there since.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.vpnView: {header: {glyph, caption,
  // iconState}, connected, available, cursor: {active, section, index},
  // emptyText, keyHint}; rows are [{key, kind, name, glyph, label}].
  // Rebuilt only when rows change.
  property var view: ({})
  // Cap on the Available scroll area's height.
  property real maxScrollHeight: Style.space(280)
  // Per-key action status: {key: {text, busy, failed}}.
  property var status: ({})
  // Per-key session details, already formatted: {key: {ip, server, up}}.
  property var sessions: ({})
  // Per-key rate samples, oldest first: {key: [{rx, tx}]}.
  property var graphs: ({})
  // The credential prompt: {key, username, password, code, busy, failed,
  // failedText}; key "" while closed.
  property var prompt: ({
      key: "",
      username: "",
      password: "",
      code: "",
      busy: false,
      failed: false,
      failedText: ""
    })
  // Showcase stand-in names (the showcase IPC method), in display order;
  // empty shows the real names.
  property var showcaseNames: []
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // The view's connected rows, or [].
  readonly property var connectedRows: view && view.connected ? view.connected : []
  // The view's available rows, or [].
  readonly property var availableRows: view && view.available ? view.available : []
  // Filters synthetic hover from rows moving under a still pointer, and
  // carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0

  // Emitted for every user action, NAME with its ARG:
  //   toggle ({index, key}): a NetworkManager row or its switch;
  //   openApp ({index, key}): an own-app row or its chip;
  //   promptSubmit, promptCancel (null): Enter and Esc in the prompt;
  //   promptConnect (null): the prompt's connect button (a pointer action);
  //   passwordEdited ({text}), codeEdited ({text}): prompt typing;
  //   hover ({section, index, key}): the pointer moved onto a row (through
  //     the gate) in "connected" or "available".
  // Row actions carry the row's key as the view saw it, so the host can
  // refuse one whose row changed underneath the click.
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved rows without rebuilding them.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // The cursor's index in SECTION, or -1 when the cursor isn't active there.
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -1
  }

  // ROWS[INDEX]'s key, or "" when there's no such row.
  function keyAt(rows, index) {
    var row = rows ? rows[index] : null
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Reports row action NAME for INDEX in ROWS, with the row's key.
  function rowAction(name, rows, index) {
    dropdown.action(name, {
      index: index,
      key: dropdown.keyAt(rows, index)
    })
  }

  // Reports a hover on SECTION's INDEX in ROWS, with the row's key.
  function hover(section, rows, index) {
    dropdown.action("hover", {
      section: section,
      index: index,
      key: dropdown.keyAt(rows, index)
    })
  }

  // Scrolls Available's INDEX row into view inside the scroll area; its
  // first row brings the caption (and the hairline above it) along. No-op
  // for the pinned Connected section or an out-of-range row. Panel calls it
  // for keyboard moves only, so the pointer never scrolls the list.
  function ensureVisible(section, index) {
    if (section !== "available")
      return
    var row = availableSection.rowWrapperAt(index)
    if (!row)
      return
    var top = index === 0 ? availableSeparator.y : row.mapToItem(scrollColumn, 0, 0).y
    var bottom = row.mapToItem(scrollColumn, 0, 0).y + row.height
    if (top < vpnScroll.contentY)
      vpnScroll.contentY = top
    else if (bottom > vpnScroll.contentY + vpnScroll.height)
      vpnScroll.contentY = bottom - vpnScroll.height
  }

  spacing: Style.space(14)

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  VpnHeader {
    width: parent.width
    glyph: dropdown.view.header ? dropdown.view.header.glyph || "" : ""
    caption: dropdown.view.header ? dropdown.view.header.caption || "" : ""
    iconState: dropdown.view.header ? dropdown.view.header.iconState || "idle" : "idle"
  }
  Separator {
    visible: connectedSection.visible
  }
  VpnSection {
    id: connectedSection
    objectName: "connectedSection"
    width: parent.width
    title: "CONNECTED"
    connected: true
    rows: dropdown.connectedRows
    status: dropdown.status
    sessions: dropdown.sessions
    graphs: dropdown.graphs
    prompt: dropdown.prompt
    showcaseNames: dropdown.showcaseNames
    nameOffset: 0
    cursorIndex: dropdown.cursorIn("connected")
    pointerGate: dropdown.pointerGate
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()
    onLayoutShifted: dropdown.noteLayoutChange()
    onToggle: function (index) {
      dropdown.rowAction("toggle", dropdown.connectedRows, index)
    }
    onOpenApp: function (index) {
      dropdown.rowAction("openApp", dropdown.connectedRows, index)
    }
    onHovered: function (index) {
      dropdown.hover("connected", dropdown.connectedRows, index)
    }
    onPromptSubmit: dropdown.action("promptSubmit", null)
    onPromptConnect: dropdown.action("promptConnect", null)
    onPromptCancel: dropdown.action("promptCancel", null)
    onPasswordEdited: function (text) {
      dropdown.action("passwordEdited", {
        text: text
      })
    }
    onCodeEdited: function (text) {
      dropdown.action("codeEdited", {
        text: text
      })
    }
  }
  Flickable {
    id: vpnScroll
    objectName: "vpnScroll"
    width: parent.width
    height: Math.min(scrollColumn.implicitHeight, dropdown.maxScrollHeight)
    // From the input, not the section's own visible: a child reads
    // invisible while its parent is, so that would latch hidden for good.
    visible: dropdown.availableRows.length > 0
    contentWidth: width
    contentHeight: scrollColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds
    onYChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
    onContentYChanged: dropdown.noteLayoutChange()

    Column {
      id: scrollColumn
      width: vpnScroll.width
      spacing: Style.space(14)
      onHeightChanged: dropdown.noteLayoutChange()

      Separator {
        id: availableSeparator
      }
      VpnSection {
        id: availableSection
        objectName: "availableSection"
        width: parent.width
        title: "AVAILABLE"
        connected: false
        rows: dropdown.availableRows
        status: dropdown.status
        sessions: dropdown.sessions
        graphs: dropdown.graphs
        prompt: dropdown.prompt
        showcaseNames: dropdown.showcaseNames
        nameOffset: dropdown.connectedRows.length
        cursorIndex: dropdown.cursorIn("available")
        pointerGate: dropdown.pointerGate
        onLayoutShifted: dropdown.noteLayoutChange()
        onToggle: function (index) {
          dropdown.rowAction("toggle", dropdown.availableRows, index)
        }
        onOpenApp: function (index) {
          dropdown.rowAction("openApp", dropdown.availableRows, index)
        }
        onHovered: function (index) {
          dropdown.hover("available", dropdown.availableRows, index)
        }
        onPromptSubmit: dropdown.action("promptSubmit", null)
        onPromptConnect: dropdown.action("promptConnect", null)
        onPromptCancel: dropdown.action("promptCancel", null)
        onPasswordEdited: function (text) {
          dropdown.action("passwordEdited", {
            text: text
          })
        }
        onCodeEdited: function (text) {
          dropdown.action("codeEdited", {
            text: text
          })
        }
      }
    }
  }
  Text {
    objectName: "emptyText"
    width: parent.width
    visible: (dropdown.view.emptyText || "") !== "" && dropdown.connectedRows.length === 0 && dropdown.availableRows.length === 0
    text: dropdown.view.emptyText || ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    text: dropdown.view.keyHint || ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The dropdown's last layout shift, for the controls' clickSettled().
    property real layoutChangedAt: dropdown.layoutChangedAt

    referenceItem: dropdown
  }
}
