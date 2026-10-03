// The Aranea Bluetooth dropdown's view: header, scanning pulse, the
// Connected/Paired/Available device sections, the empty text and a
// key-hint line, drawn from one plain view object (Panel.bluetoothView)
// and reporting every user action through a single action signal. No
// Bluetooth objects here, so tests drive it with fixtures.
//
// Header and Connected are pinned; Paired and Available scroll together
// inside a Flickable (objectName "deviceScroll") capped at
// maxScrollHeight, the same shape as stock's pinned-connected-list-over-
// ListView.
//
// Anything that moves rows or the power switch under a still pointer
// without the pointer moving (a section's devices changing, a section
// showing or hiding, the scanning pulse changing the header's height)
// stamps layoutChangedAt, which the rows, their forget buttons and
// right-click areas and the power switch read through pointerGate: a click
// within 300 ms of it is ignored unless the pointer has really moved there
// since.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.bluetoothView.
  property var view: ({})
  // Cap on the Paired/Available scroll area's height, so a noisy
  // neighbourhood doesn't grow the popup past the screen.
  property real maxScrollHeight: Style.space(400)
  // The header caption's opacity, animated by Panel between rotating
  // phrases. Kept out of view so the fade never rebuilds the view object.
  property real captionOpacity: 1
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1,
      action: false
    })
  // Whether the adapter is present and on: gates Available and the scanning
  // pulse here rather than trusting the view to send empty arrays while it's
  // off. Connected and Paired need only an adapter: stock keeps Paired on
  // screen while the adapter is off, and choosing a device powers it on.
  readonly property bool devicesAvailable: !!dropdown.view.enabled && !!dropdown.view.hasAdapter
  // Filters synthetic hover from rows and controls moving under a still
  // pointer (e.g. a device list changing underneath the cursor), and
  // carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // The power switch's state from the view ({on, busy}), or the adapter's
  // own with nothing pending.
  readonly property var power: dropdown.view && dropdown.view.power ? dropdown.view.power : ({
      on: !!dropdown.view.enabled,
      busy: false
    })
  // Each section's device keys joined, so an equal list rebuilt by the
  // host does not stamp the layout.
  readonly property string connectedKeys: dropdown.joinKeys(connectedSection.rows)
  // The Paired section's keys joined (see connectedKeys).
  readonly property string knownKeys: dropdown.joinKeys(pairedSection.rows)
  // The Available section's keys joined (see connectedKeys).
  readonly property string discoveredKeys: dropdown.joinKeys(availableSection.rows)

  // Stamps layoutChangedAt: something moved rows without rebuilding them.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // ROWS' keys joined by newlines, "" for none.
  function joinKeys(rows) {
    return (rows || []).map(function (r) {
      return r && typeof r.key === "string" ? r.key : ""
    }).join("\n")
  }

  // The rows SECTION shows ("connected", "known" or "discovered").
  function sectionRows(section) {
    var sec = section === "connected" ? connectedSection : section === "known" ? pairedSection : section === "discovered" ? availableSection : null
    return sec ? sec.rows : []
  }

  // Reports row action NAME for SECTION's row INDEX holding KEY, refused
  // when that row no longer carries KEY (the list changed underneath).
  function rowAction(name, section, index, key) {
    var row = dropdown.sectionRows(section)[index]
    if (!row || row.key !== key)
      return
    dropdown.action(name, {
      section: section,
      index: index,
      key: key
    })
  }

  // Reports a hover on SECTION's row INDEX: ACTION true on its forget
  // button; HOVERED false (leaving the button) adds leave: true.
  function rowHover(section, index, action, hovered) {
    dropdown.action("hover", hovered ? {
      section: section,
      index: index,
      action: action
    } : {
      section: section,
      index: index,
      action: false,
      leave: true
    })
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // Emitted for every user action, NAME with its ARG:
  //   toggleBluetooth (null): the power switch was toggled;
  //   primary ({section, index, key}): a row was chosen (connect,
  //     disconnect, pair);
  //   secondary ({section, index, key}): a row was right-clicked;
  //   forget ({section, index, key}): a row's forget button was clicked;
  //   row actions carry the row's key (the device address) as the view
  //   held it, and are never sent when the row's key changed underneath;
  //   hover ({section, index, action}): the pointer entered the switch
  //     (section "header"), a row (action false) or a forget button (action
  //     true). Leaving a forget button adds leave: true, so the host only
  //     drops the action focus there instead of moving the cursor.
  signal action(string name, var arg)

  // Cursor row index for SECTION: the view's index there, else -2 (none).
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -2
  }

  // Scrolls SECTION's INDEX row ("known" or "discovered") into view inside
  // the Paired/Available scroll area, e.g. after a keyboard move lands on
  // a row below or above the fold; for INDEX 0 the section's caption comes
  // into view too. No-op for "connected" (pinned, always
  // visible) or an out-of-range row.
  function ensureVisible(section, index) {
    var sec = section === "known" ? pairedSection : section === "discovered" ? availableSection : null
    if (!sec)
      return
    var wrapperItem = sec.rowWrapperAt(index)
    if (!wrapperItem)
      return
    // A section's first row brings its caption (and the hairline above
    // it) along, so scrolling back up never stops just under the caption.
    var top = index === 0 ? sec.mapToItem(scrollColumn, 0, 0).y : wrapperItem.mapToItem(scrollColumn, 0, 0).y
    var bottom = top + wrapperItem.height
    if (top < deviceScroll.contentY)
      deviceScroll.contentY = top
    else if (bottom > deviceScroll.contentY + deviceScroll.height)
      deviceScroll.contentY = bottom - deviceScroll.height
  }

  spacing: Style.space(14)
  onConnectedKeysChanged: dropdown.noteLayoutChange()
  onKnownKeysChanged: dropdown.noteLayoutChange()
  onDiscoveredKeysChanged: dropdown.noteLayoutChange()

  BluetoothHeader {
    width: parent.width
    glyph: dropdown.view.glyph || ""
    caption: dropdown.view.caption || ""
    captionOpacity: dropdown.captionOpacity
    powered: !!dropdown.power.on
    busy: !!dropdown.power.busy
    hasAdapter: !!dropdown.view.hasAdapter
    hint: dropdown.view.toggleHint || ""
    hasCursor: !!dropdown.view.headerCursor
    pointerGate: dropdown.pointerGate
    onToggleBluetooth: dropdown.action("toggleBluetooth", null)
    onEntered: dropdown.action("hover", {
      section: "header",
      index: -1,
      action: false
    })
  }
  Aranea.FilamentPulse {
    objectName: "scanPulse"
    width: parent.width
    running: !!dropdown.view.open && dropdown.devicesAvailable && !!dropdown.view.scanning
    // The pulse shows only while scanning: it moves everything below it.
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Rectangle {
    width: parent.width
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
    visible: connectedSection.visible
  }
  BluetoothDeviceSection {
    id: connectedSection
    objectName: "connectedSection"
    width: parent.width
    sectionName: "connected"
    caption: "CONNECTED"
    countText: String((dropdown.view.connected || []).length)
    rows: dropdown.view.hasAdapter ? (dropdown.view.connected || []) : []
    signals: dropdown.view.signals || ({})
    cursor: dropdown.cursorIn("connected")
    pointerGate: dropdown.pointerGate
    cursorAction: !!dropdown.cursor.action
    rowTooltip: "Disconnect"
    // Showing or hiding moves everything below it.
    onVisibleChanged: dropdown.noteLayoutChange()
    onPrimary: function (index, key) {
      dropdown.rowAction("primary", "connected", index, key)
    }
    onSecondary: function (index, key) {
      dropdown.rowAction("secondary", "connected", index, key)
    }
    onForget: function (index, key) {
      dropdown.rowAction("forget", "connected", index, key)
    }
    onRowHovered: function (index) {
      dropdown.rowHover("connected", index, false, true)
    }
    onActionHovered: function (index, hovered) {
      dropdown.rowHover("connected", index, true, hovered)
    }
  }
  Flickable {
    id: deviceScroll
    objectName: "deviceScroll"
    width: parent.width
    height: Math.min(scrollColumn.implicitHeight, dropdown.maxScrollHeight)
    contentWidth: width
    contentHeight: scrollColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: scrollColumn
      width: deviceScroll.width
      spacing: Style.space(14)

      Rectangle {
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
        visible: pairedSection.visible
      }
      BluetoothDeviceSection {
        id: pairedSection
        objectName: "pairedSection"
        width: parent.width
        sectionName: "known"
        caption: "PAIRED"
        countText: String((dropdown.view.known || []).length)
        rows: dropdown.view.hasAdapter ? (dropdown.view.known || []) : []
        signals: dropdown.view.signals || ({})
        cursor: dropdown.cursorIn("known")
        pointerGate: dropdown.pointerGate
        cursorAction: !!dropdown.cursor.action
        rowTooltip: "Connect"
        // Showing or hiding moves everything below it.
        onVisibleChanged: dropdown.noteLayoutChange()
        onPrimary: function (index, key) {
          dropdown.rowAction("primary", "known", index, key)
        }
        onSecondary: function (index, key) {
          dropdown.rowAction("secondary", "known", index, key)
        }
        onForget: function (index, key) {
          dropdown.rowAction("forget", "known", index, key)
        }
        onRowHovered: function (index) {
          dropdown.rowHover("known", index, false, true)
        }
        onActionHovered: function (index, hovered) {
          dropdown.rowHover("known", index, true, hovered)
        }
      }
      Rectangle {
        width: parent.width
        height: Math.max(1, Style.spacing.hairline)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
        visible: availableSection.visible
      }
      BluetoothDeviceSection {
        id: availableSection
        objectName: "availableSection"
        width: parent.width
        sectionName: "discovered"
        caption: "AVAILABLE"
        countText: "scanning"
        rows: dropdown.devicesAvailable && dropdown.view.scanning ? (dropdown.view.discovered || []) : []
        signals: dropdown.view.signals || ({})
        cursor: dropdown.cursorIn("discovered")
        pointerGate: dropdown.pointerGate
        cursorAction: !!dropdown.cursor.action
        rowTooltip: "Pair"
        // Showing or hiding moves everything below it.
        onVisibleChanged: dropdown.noteLayoutChange()
        onPrimary: function (index, key) {
          dropdown.rowAction("primary", "discovered", index, key)
        }
        onSecondary: function (index, key) {
          dropdown.rowAction("secondary", "discovered", index, key)
        }
        onForget: function (index, key) {
          dropdown.rowAction("forget", "discovered", index, key)
        }
        onRowHovered: function (index) {
          dropdown.rowHover("discovered", index, false, true)
        }
        onActionHovered: function (index, hovered) {
          dropdown.rowHover("discovered", index, true, hovered)
        }
      }
    }
  }
  Text {
    objectName: "emptyText"
    width: parent.width
    visible: (dropdown.view.emptyText || "") !== ""
    text: dropdown.view.emptyText || ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    text: "↑↓ move · enter connect · x forget · b power · tab next"
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
