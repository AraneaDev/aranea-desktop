// The Aranea Clock dropdown's SUN & MOON section: the caption with the
// place on the right, the sun arc, and a two-column grid of today's
// sunrise, sunset, daylight and the moon (glyph, phase and illumination).
// Without sun data (no location yet) the arc and the sun times hide and
// the moon stays; after sunset a "Night" caption sits under the arc (its
// dot dim at the horizon); a polar day or night shows its caption in place
// of the sunrise and sunset. Pure view: the host hides the whole section when
// there is nothing to show.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: sky

  // The view's sky: {visible, place, sun: {visible, sunrise, sunset,
  // daylight, arcT, night, polar}, moon: {glyph, name, illumination}}.
  property var skyView: ({})
  // The sun part, or a hidden one.
  readonly property var sun: skyView && skyView.sun ? skyView.sun : ({
      visible: false
    })
  // The moon part, or null.
  readonly property var moon: skyView && skyView.moon && skyView.moon.name ? skyView.moon : null
  // Whether the sun shows (the arc and whatever times it has).
  readonly property bool sunShown: !!sun.visible
  // "day" or "night" for a polar sun, else "".
  readonly property string polar: sunShown && (sun.polar === "day" || sun.polar === "night") ? sun.polar : ""
  // Whether the sunrise and sunset pairs show.
  readonly property bool timesShown: sunShown && polar === ""
  // Whether the daylight pair shows.
  readonly property bool daylightShown: sunShown && !!sun.daylight
  // The moon line, e.g. "<glyph> Waning gibbous · 68%".
  readonly property string moonText: moon ? (moon.glyph ? moon.glyph + " " : "") + moon.name + " · " + Math.round(Number(moon.illumination) || 0) + "%" : ""

  spacing: Style.space(4)

  // A muted label and a value, the value on the pair's right edge.
  component Pair: Item {
    id: pair
    // The label, e.g. "Sunrise".
    property string label: ""
    // The value, e.g. "07:43".
    property string value: ""
    // The value's objectName, for tests.
    property string valueName: ""

    implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)
    Text {
      id: pairLabel
      anchors.left: parent.left
      anchors.right: pairValue.left
      anchors.rightMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: pair.label
      elide: Text.ElideRight
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
    Text {
      id: pairValue
      objectName: pair.valueName
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: pair.value
      color: Aranea.DesignTokens.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Item {
    width: sky.width
    implicitHeight: Math.max(skyTitle.implicitHeight, skyPlace.implicitHeight)
    Text {
      id: skyTitle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "SUN & MOON"
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 1.2
    }
    Text {
      id: skyPlace
      objectName: "skyPlace"
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, parent.width - skyTitle.implicitWidth - Style.space(12))
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideRight
      text: sky.skyView && sky.skyView.place ? String(sky.skyView.place) : ""
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
  ClockArc {
    width: sky.width
    visible: sky.sunShown
    arcT: Number(sky.sun.arcT) || 0
    night: !!sky.sun.night
    polar: sky.polar
  }
  Text {
    objectName: "polarCaption"
    width: sky.width
    visible: sky.polar !== ""
    text: sky.polar === "day" ? "Sun up all day" : sky.polar === "night" ? "Sun down all day" : ""
    color: Aranea.DesignTokens.foreground
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Text {
    objectName: "nightCaption"
    width: sky.width
    visible: sky.timesShown && !!sky.sun.night
    text: "Night"
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Grid {
    id: pairs
    // Each pair's width: half the row.
    readonly property real pairWidth: (width - columnSpacing) / 2
    width: sky.width
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(4)

    Pair {
      width: pairs.pairWidth
      visible: sky.timesShown
      label: "Sunrise"
      value: sky.sun.sunrise || ""
      valueName: "sunriseValue"
    }
    Pair {
      width: pairs.pairWidth
      visible: sky.timesShown
      label: "Sunset"
      value: sky.sun.sunset || ""
      valueName: "sunsetValue"
    }
    Pair {
      width: pairs.pairWidth
      visible: sky.daylightShown
      label: "Daylight"
      value: sky.sun.daylight || ""
      valueName: "daylightValue"
    }
    Pair {
      // Alone on its row (no daylight), the moon takes the full width.
      width: sky.daylightShown ? pairs.pairWidth : pairs.width
      visible: sky.moon !== null
      label: "Moon"
      value: sky.moonText
      valueName: "moonValue"
    }
  }
}
