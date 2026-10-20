// Pure world-clock view: no settings, processes or ticking clocks.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: dropdown
  // Runtime font token object; the host supplies its members dynamically.
  readonly property var fontSizes: Style.font
  // Plain home, sun, row and search presentation state.
  property var view: ({})
  // Saved-city row models from the view.
  readonly property var rows: view.rows || []
  // Whether the inline city editor owns keyboard input.
  readonly property bool adding: !!view.adding
  // Reports a named user action and its scalar argument to the controller.
  signal action(string name, var arg)
  // Lets a scroll host reveal the selected row or inline editor after layout.
  signal revealRequested(real top, real rowHeight)
  // Emits the currently selected row or editor bounds in dropdown coordinates.
  function revealCurrent() {
    let item = dropdown.adding ? search : null
    if (!item) {
      for (let i = 0; i < dropdown.rows.length; i++)
        if (dropdown.rows[i].selected) {
          item = zoneRepeater.itemAt(i)
          break
        }
    }
    if (item)
      dropdown.revealRequested(item.mapToItem(dropdown, 0, 0).y, item.height)
  }
  spacing: Style.space(8)
  // Hands keyboard focus to the city editor after its layout is visible.
  function focusQuery() {
    search.focusQuery()
  }
  component Section: Item {
    property string title
    property string caption
    implicitHeight: Style.space(18)
    Aranea.UiLabel {
      text: parent.title
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      font.bold: true
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.82)
    }
    Aranea.UiLabel {
      text: parent.caption
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.5)
    }
  }
  Aranea.DropdownHeader {
    width: parent.width
    refined: true
    title: "World clock"
    glyph: String.fromCodePoint(0xf01e7)
    caption: dropdown.rows.length + " ZONES · HOME " + String(dropdown.view.homeName || "").toUpperCase()
    Column {
      Text {
        objectName: "homeTime"
        anchors.right: parent.right
        text: dropdown.view.homeTime || "-:-"
        color: Aranea.DesignTokens.accent
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: dropdown.fontSizes.display
      }
      Text {
        objectName: "utcTime"
        anchors.right: parent.right
        text: "UTC " + (dropdown.view.utcTime || "-:-")
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.5)
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: dropdown.fontSizes.caption
      }
      // Explicit width keeps the right-aligned children inside the trailing slot.
      width: Math.max(children[0].implicitWidth, children[1].implicitWidth)
    }
  }
  Section {
    width: parent.width
    title: "SUN"
    caption: dropdown.view.sunCaption || ""
  }
  Globe {
    id: globe
    objectName: "worldGlobe"
    width: Math.min(dropdown.width, Style.space(300))
    height: Style.space(236)
    anchors.horizontalCenter: parent.horizontalCenter
    sun: dropdown.view.sun || ({
        lat: 0,
        lon: 0
      })
    homeLon: {
      let home = dropdown.rows.find(function (r) {
        return r.home && r.place
      })
      return home ? Number(home.place.lon) || 0 : 0
    }
    markers: {
      let list = dropdown.rows.filter(function (r) {
        return r.place && typeof r.place.lat === "number" && typeof r.place.lon === "number"
      }).map(function (r) {
        return {
          lat: r.place.lat,
          lon: r.place.lon,
          role: r.selected ? "selected" : r.home ? "home" : "other",
          label: r.name,
          night: r.node === "night"
        }
      })
      let p = dropdown.adding ? dropdown.view.selectedPlace : null
      if (p && typeof p.lat === "number" && typeof p.lon === "number")
        list.push({
          lat: p.lat,
          lon: p.lon,
          role: "selected",
          label: p.name,
          night: false
        })
      return list
    }
  }
  Section {
    width: parent.width
    title: "ZONES"
    caption: String(dropdown.rows.length)
  }
  Column {
    width: parent.width
    Repeater {
      id: zoneRepeater
      model: dropdown.rows
      ZoneRow {
        required property var modelData
        required property int index
        objectName: "zoneRow"
        width: dropdown.width
        row: modelData
        onClicked: dropdown.action("select", index)
        onPreviewRequested: if (!dropdown.adding)
          dropdown.action("select", index)
      }
    }
    Item {
      objectName: "addCity"
      visible: !dropdown.adding
      width: parent.width
      height: Style.space(30)
      Aranea.HoverTint {}
      Aranea.UiLabel {
        x: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        text: "+"
        color: Aranea.DesignTokens.accent
        font.pixelSize: dropdown.fontSizes.body
      }
      Aranea.UiLabel {
        x: Style.space(32)
        anchors.verticalCenter: parent.verticalCenter
        text: "Add city"
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.6)
        font.pixelSize: dropdown.fontSizes.body
      }
      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: dropdown.action("addStart", null)
      }
    }
    CitySearch {
      id: search
      width: parent.width
      visible: dropdown.adding
      query: dropdown.view.query || ""
      matches: dropdown.view.matches || []
      onAction: function (name, arg) {
        dropdown.action(name, arg)
      }
    }
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    text: dropdown.adding ? "↑↓ choose · enter add · esc cancel" : "↑↓ move · a add · x remove · [ ] reorder · h set home"
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Math.max(1, dropdown.fontSizes.caption - 1)
    elide: Text.ElideRight
  }
  onImplicitHeightChanged: Qt.callLater(dropdown.revealCurrent)
  onViewChanged: {
    Qt.callLater(dropdown.revealCurrent)
    let p = dropdown.view.selectedPlace
    if (p && typeof p.lat === "number" && typeof p.lon === "number")
      globe.previewTo(p.lat, p.lon)
    else if (!dropdown.adding)
      globe.easeHome()
  }
}
