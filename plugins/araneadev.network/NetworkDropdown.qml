// The Aranea Network dropdown's view: the header, then the pinned Link,
// Interfaces, VPN, Band and DNS sections, then the Wi-Fi list and the
// Saved profiles scrolling together in a Flickable (objectName
// "wifiScroll") capped at maxScrollHeight, the empty text and a key-hint
// line. Drawn from one plain view object (Panel.networkView) plus a few
// fast-changing properties kept out of it, and reporting every user
// action through a single action signal. No NetworkManager objects here,
// so tests drive it with fixtures.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.networkView: {header, interfaces, vpn, band,
  // dns, wifi, saved, cursor, emptyText}. Rebuilt only when rows change.
  property var view: ({})
  // Cap on the Wi-Fi/Saved scroll area's height, so a busy neighbourhood
  // doesn't grow the popup past the screen.
  property real maxScrollHeight: Style.space(280)
  // The header caption's opacity, animated by Panel between phrases.
  property real captionOpacity: 1
  // The Link stats, already formatted (NetworkLinkSection's shape).
  property var stats: ({})
  // Rate samples for the graph, oldest first: [{rx, tx}].
  property var graph: []
  // Per-SSID Wi-Fi action status: {ssid: {text, failed, busy}}.
  property var wifiStatus: ({})
  // Per-uuid VPN action state: {uuid: {busy, failed}}.
  property var vpnStatus: ({})
  // The passphrase prompt: {ssid, enterprise, busy, failed, passphrase,
  // identity}; ssid "" while closed.
  property var prompt: ({
      ssid: "",
      enterprise: false,
      busy: false,
      failed: false,
      passphrase: "",
      identity: ""
    })
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1,
      action: false,
      bandAuto: false
    })
  // The view's Wi-Fi part, or an empty one.
  readonly property var wifi: view && view.wifi ? view.wifi : ({
      available: false,
      scanning: false,
      rows: []
    })
  // The view's band part, or a hidden one.
  readonly property var band: view && view.band ? view.band : ({
      visible: false
    })
  // Filters synthetic hover from rows and controls moving under a still
  // pointer (e.g. the Wi-Fi list changing underneath the cursor).
  readonly property alias pointerGate: gate

  // Emitted for every user action, NAME with its ARG:
  //   qr, speed, toggleWifi (null): the header's actions;
  //   copy ({value}): a copyable Link value was clicked;
  //   vpnToggle ({index}): a VPN row or its switch;
  //   bandAuto (null): the band's Automatic switch;
  //   band ({key}), dns ({key}): a band or DNS pill;
  //   wifiPrimary ({index}), wifiForget ({index}): a Wi-Fi row, its forget;
  //   promptSubmit, promptCancel (null): the passphrase prompt;
  //   passphraseEdited ({text}), identityEdited ({text}): prompt typing;
  //   savedForget ({index}): a Saved row's forget;
  //   hover ({section, index, action}): the pointer moved onto something
  //     (through the gate) in "header", "vpn", "band" (adds auto: true for
  //     the Automatic switch, index 0), "dns", "wifi" or "saved"; action is
  //     true on a forget button. Leaving a forget button adds leave: true,
  //     so the host only drops the action focus there.
  signal action(string name, var arg)

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // The cursor's index in SECTION, or -1 when the cursor isn't active there.
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -1
  }

  // Reports a hover on SECTION's INDEX (ACTION on its forget button).
  function hover(section, index, action) {
    dropdown.action("hover", {
      section: section,
      index: index,
      action: action
    })
  }

  // Reports the pointer leaving SECTION's INDEX's forget button.
  function leaveAction(section, index) {
    dropdown.action("hover", {
      section: section,
      index: index,
      action: false,
      leave: true
    })
  }

  // Scrolls SECTION's ("wifi" or "saved") INDEX row into view inside the
  // scroll area; a section's first row brings its caption (and the
  // hairline above it) along. No-op for
  // pinned sections or an out-of-range row. Panel calls it for keyboard
  // moves only, so the pointer never scrolls the list.
  function ensureVisible(section, index) {
    if (section !== "wifi" && section !== "saved")
      return
    var row = section === "wifi" ? wifiSection.rowWrapperAt(index) : savedSection.rowWrapperAt(index)
    if (!row)
      return
    var sep = section === "wifi" ? wifiSeparator : savedSeparator
    var top = index === 0 ? sep.y : row.mapToItem(scrollColumn, 0, 0).y
    var bottom = row.mapToItem(scrollColumn, 0, 0).y + row.height
    if (top < wifiScroll.contentY)
      wifiScroll.contentY = top
    else if (bottom > wifiScroll.contentY + wifiScroll.height)
      wifiScroll.contentY = bottom - wifiScroll.height
  }

  spacing: Style.space(14)

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  NetworkHeader {
    width: parent.width
    glyph: dropdown.view.header ? dropdown.view.header.glyph || "" : ""
    title: dropdown.view.header ? dropdown.view.header.title || "" : ""
    caption: dropdown.view.header ? dropdown.view.header.caption || "" : ""
    captionOpacity: dropdown.captionOpacity
    canQr: !!(dropdown.view.header && dropdown.view.header.canQr)
    canSpeed: !!(dropdown.view.header && dropdown.view.header.canSpeed)
    canToggle: !!(dropdown.view.header && dropdown.view.header.canToggle)
    wifiOn: !!(dropdown.view.header && dropdown.view.header.wifiOn)
    toggleHint: dropdown.view.header ? dropdown.view.header.toggleHint || "" : ""
    scanning: !!(dropdown.view.header && dropdown.view.header.scanning)
    cursorIndex: dropdown.cursorIn("header")
    pointerGate: dropdown.pointerGate
    onQr: dropdown.action("qr", null)
    onSpeed: dropdown.action("speed", null)
    onToggleWifi: dropdown.action("toggleWifi", null)
    onHoverAction: function (index) {
      dropdown.hover("header", index, false)
    }
  }
  Separator {
    visible: linkSection.visible
  }
  NetworkLinkSection {
    id: linkSection
    width: parent.width
    stats: dropdown.stats
    samples: dropdown.graph
    pointerGate: dropdown.pointerGate
    onCopy: function (value) {
      dropdown.action("copy", {
        value: value
      })
    }
  }
  Separator {
    visible: interfacesSection.visible
  }
  NetworkInterfacesSection {
    id: interfacesSection
    width: parent.width
    rows: dropdown.view.interfaces || []
  }
  Separator {
    visible: vpnSection.visible
  }
  NetworkVpnSection {
    id: vpnSection
    width: parent.width
    rows: dropdown.view.vpn || []
    status: dropdown.vpnStatus
    cursorIndex: dropdown.cursorIn("vpn")
    pointerGate: dropdown.pointerGate
    onToggle: function (index) {
      dropdown.action("vpnToggle", {
        index: index
      })
    }
    onRowHovered: function (index) {
      dropdown.hover("vpn", index, false)
    }
  }
  Separator {
    visible: bandSection.visible
  }
  NetworkBandSection {
    id: bandSection
    width: parent.width
    visible: !!dropdown.band.visible
    title: dropdown.band.title || ""
    auto: dropdown.band.auto !== false
    currentLabel: dropdown.band.currentLabel || ""
    pillsVisible: !!dropdown.band.pillsVisible
    options: dropdown.band.options || []
    busy: !!dropdown.band.busy
    cursorAuto: dropdown.cursor.active && dropdown.cursor.section === "band" && !!dropdown.cursor.bandAuto
    cursorIndex: dropdown.cursor.active && dropdown.cursor.section === "band" && !dropdown.cursor.bandAuto ? dropdown.cursor.index : -1
    pointerGate: dropdown.pointerGate
    onToggleAuto: dropdown.action("bandAuto", null)
    onPick: function (key) {
      dropdown.action("band", {
        key: key
      })
    }
    onPillHovered: function (auto, index) {
      dropdown.action("hover", {
        section: "band",
        index: auto ? 0 : index,
        action: false,
        auto: auto
      })
    }
  }
  Separator {
    visible: dnsSection.visible
  }
  NetworkDnsSection {
    id: dnsSection
    width: parent.width
    visible: options.length > 0
    options: dropdown.view.dns && dropdown.view.dns.options ? dropdown.view.dns.options : []
    cursorIndex: dropdown.cursorIn("dns")
    pointerGate: dropdown.pointerGate
    onPick: function (key) {
      dropdown.action("dns", {
        key: key
      })
    }
    onPillHovered: function (index) {
      dropdown.hover("dns", index, false)
    }
  }
  Flickable {
    id: wifiScroll
    objectName: "wifiScroll"
    width: parent.width
    height: Math.min(scrollColumn.implicitHeight, dropdown.maxScrollHeight)
    visible: wifiSection.visible || savedSection.visible
    contentWidth: width
    contentHeight: scrollColumn.implicitHeight
    clip: true
    interactive: contentHeight > height
    boundsBehavior: Flickable.StopAtBounds

    Column {
      id: scrollColumn
      width: wifiScroll.width
      spacing: Style.space(14)

      Separator {
        id: wifiSeparator
        visible: wifiSection.visible
      }
      NetworkWifiSection {
        id: wifiSection
        width: parent.width
        rows: dropdown.wifi.rows || []
        status: dropdown.wifiStatus
        prompt: dropdown.prompt
        scanning: !!dropdown.wifi.scanning
        available: !!dropdown.wifi.available
        cursorIndex: dropdown.cursorIn("wifi")
        cursorAction: !!dropdown.cursor.action
        pointerGate: dropdown.pointerGate
        onPrimary: function (index) {
          dropdown.action("wifiPrimary", {
            index: index
          })
        }
        onForget: function (index) {
          dropdown.action("wifiForget", {
            index: index
          })
        }
        onHovered: function (index, action) {
          dropdown.hover("wifi", index, action)
        }
        onActionLeft: function (index) {
          dropdown.leaveAction("wifi", index)
        }
        onPromptSubmit: dropdown.action("promptSubmit", null)
        onPromptCancel: dropdown.action("promptCancel", null)
        onPassphraseEdited: function (text) {
          dropdown.action("passphraseEdited", {
            text: text
          })
        }
        onIdentityEdited: function (text) {
          dropdown.action("identityEdited", {
            text: text
          })
        }
      }
      Separator {
        id: savedSeparator
        visible: savedSection.visible
      }
      NetworkSavedSection {
        id: savedSection
        width: parent.width
        rows: dropdown.view.saved || []
        cursorIndex: dropdown.cursorIn("saved")
        cursorAction: !!dropdown.cursor.action
        pointerGate: dropdown.pointerGate
        onForget: function (index) {
          dropdown.action("savedForget", {
            index: index
          })
        }
        onHovered: function (index, action) {
          dropdown.hover("saved", index, action)
        }
        onActionLeft: function (index) {
          dropdown.leaveAction("saved", index)
        }
      }
    }
  }
  Text {
    objectName: "emptyText"
    width: parent.width
    visible: (dropdown.view.emptyText || "") !== "" && (dropdown.wifi.rows || []).length === 0 && (dropdown.view.saved || []).length === 0 && !dropdown.wifi.available
    text: dropdown.view.emptyText || ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    text: "↑↓ move · ←→ pick · enter connect · x forget · tab next"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    referenceItem: dropdown
  }
}
