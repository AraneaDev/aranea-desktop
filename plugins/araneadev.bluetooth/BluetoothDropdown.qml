// The Aranea Bluetooth dropdown's view: header, scanning pulse, the
// Connected/Paired/Available device sections, the empty text and a
// key-hint line, drawn from one plain view object (Panel.bluetoothView)
// and reporting every user action through a single action signal. No
// Bluetooth objects here, so tests drive it with fixtures.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.bluetoothView.
  property var view: ({})
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1,
      action: false
    })

  // Emitted for every user action: toggleBluetooth, primary, secondary,
  // forget and hover. See the plan's action list.
  signal action(string name, var arg)

  // Cursor row index for SECTION: the view's index there, else -2 (none).
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -2
  }

  spacing: Style.space(14)

  BluetoothHeader {
    width: parent.width
    glyph: dropdown.view.glyph || ""
    caption: dropdown.view.caption || ""
    powered: !!dropdown.view.enabled
    hasAdapter: !!dropdown.view.hasAdapter
    hint: dropdown.view.toggleHint || ""
    hasCursor: !!dropdown.view.headerCursor
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
    running: !!dropdown.view.scanning
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
    rows: dropdown.view.connected || []
    signals: dropdown.view.signals || ({})
    cursor: dropdown.cursorIn("connected")
    cursorAction: !!dropdown.cursor.action
    rowTooltip: "Disconnect"
    onPrimary: function (index) {
      dropdown.action("primary", {
        section: "connected",
        index: index
      })
    }
    onSecondary: function (index) {
      dropdown.action("secondary", {
        section: "connected",
        index: index
      })
    }
    onForget: function (index) {
      dropdown.action("forget", {
        section: "connected",
        index: index
      })
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "connected",
        index: index,
        action: false
      })
    }
  }
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
    rows: dropdown.view.known || []
    signals: dropdown.view.signals || ({})
    cursor: dropdown.cursorIn("known")
    cursorAction: !!dropdown.cursor.action
    rowTooltip: "Connect"
    onPrimary: function (index) {
      dropdown.action("primary", {
        section: "known",
        index: index
      })
    }
    onSecondary: function (index) {
      dropdown.action("secondary", {
        section: "known",
        index: index
      })
    }
    onForget: function (index) {
      dropdown.action("forget", {
        section: "known",
        index: index
      })
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "known",
        index: index,
        action: false
      })
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
    rows: dropdown.view.scanning ? (dropdown.view.discovered || []) : []
    signals: dropdown.view.signals || ({})
    cursor: dropdown.cursorIn("discovered")
    cursorAction: !!dropdown.cursor.action
    rowTooltip: "Pair"
    onPrimary: function (index) {
      dropdown.action("primary", {
        section: "discovered",
        index: index
      })
    }
    onSecondary: function (index) {
      dropdown.action("secondary", {
        section: "discovered",
        index: index
      })
    }
    onForget: function (index) {
      dropdown.action("forget", {
        section: "discovered",
        index: index
      })
    }
    onRowHovered: function (index) {
      dropdown.action("hover", {
        section: "discovered",
        index: index,
        action: false
      })
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
    width: parent.width
    text: "↑↓ move · → forget · enter connect · x forget · tab next"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}
