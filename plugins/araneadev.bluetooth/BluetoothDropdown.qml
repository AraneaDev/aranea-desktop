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
import QtQuick
import qs.Commons
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

  // Emitted for every user action, NAME with its ARG:
  //   toggleBluetooth (null): the power switch was toggled;
  //   primary ({section, index}): a row was chosen (connect, disconnect, pair);
  //   secondary ({section, index}): a row was right-clicked;
  //   forget ({section, index}): a row's forget button was clicked;
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

  BluetoothHeader {
    width: parent.width
    glyph: dropdown.view.glyph || ""
    caption: dropdown.view.caption || ""
    captionOpacity: dropdown.captionOpacity
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
    running: !!dropdown.view.open && dropdown.devicesAvailable && !!dropdown.view.scanning
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
    onActionHovered: function (index, hovered) {
      dropdown.action("hover", hovered ? {
        section: "connected",
        index: index,
        action: true
      } : {
        section: "connected",
        index: index,
        action: false,
        leave: true
      })
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
        onActionHovered: function (index, hovered) {
          dropdown.action("hover", hovered ? {
            section: "known",
            index: index,
            action: true
          } : {
            section: "known",
            index: index,
            action: false,
            leave: true
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
        rows: dropdown.devicesAvailable && dropdown.view.scanning ? (dropdown.view.discovered || []) : []
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
        onActionHovered: function (index, hovered) {
          dropdown.action("hover", hovered ? {
            section: "discovered",
            index: index,
            action: true
          } : {
            section: "discovered",
            index: index,
            action: false,
            leave: true
          })
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
}
