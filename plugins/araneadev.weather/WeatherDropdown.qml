// The Aranea Weather dropdown's view: the hero (condition glyph, big
// temperature and label, the place and the updated label, rain soon and a
// loading strand), the place edit and its suggestions while editing, the
// details grid (feels, humidity, wind with its arrow, gusts, pressure with
// its trend, visibility), NEXT 24 H (the temperature trace over rain-chance
// bars), AIR & UV chips, the forecast days and the key hint. Drawn from one
// plain view object (Panel's weather view) plus hourlyPoints and editText
// kept out of it, and reporting every user action through a single action
// signal. No requests, settings or processes here: tests drive it with
// fixtures.
//
// The keyboard cursor outline shows only while view.cursor.active, never on
// hover; hover goes through a PointerMoveGate only. Suggestions are keyed
// by name and coordinates and never rebuilt for a new highlight. Every
// section showing, hiding or changing height, and the suggestion keys
// changing, and the place editor opening or closing, stamps
// layoutChangedAt; a click within 300 ms of that, or of
// its control being built, is ignored unless the pointer has really moved
// onto it since, and a pick whose key no longer matches its row is refused.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel's weather view: {hero: {glyph, temp, label,
  // place, updated, loading}, rainSoon (or ""), details: [{key, label,
  // value, arrow? (degrees, the wind's), dir?, trend?}], hourly: {visible,
  // caption, labels: [text]}, air: {aqi: {visible, text, tone ("good",
  // "plain" or "bad")}, uv: {visible, text}}, days: [{key (the date),
  // label, glyph, hi, lo}], edit: {active, suggestions: [{key (name
  // and coordinates), name, description}], saving, cursor (the highlighted
  // suggestion, -1 for none)}, cursor: {active, section ("place",
  // "refresh", "clear"), index}, keyHint}.
  property var view: ({})
  // WeatherLogic.hourlyPoints's result ({temp, rain, min, max, now}), or
  // null: NEXT 24 H hides without temperature points.
  property var hourlyPoints: null
  // The place field's text when editing starts (or the host resets it).
  property string editText: ""
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from controls moving under a still pointer,
  // and carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // The view's hero part, or an empty one.
  readonly property var hero: view && view.hero ? view.hero : ({})
  // The view's detail cells, or [].
  readonly property var details: view && Array.isArray(view.details) ? view.details : []
  // The view's hourly part, or a hidden one.
  readonly property var hourly: view && view.hourly ? view.hourly : ({
      visible: false
    })
  // The view's air part, or one with both chips hidden.
  readonly property var air: view && view.air ? view.air : ({})
  // The view's forecast days, or [].
  readonly property var days: view && Array.isArray(view.days) ? view.days : []
  // The view's edit part, or a closed one.
  readonly property var edit: view && view.edit ? view.edit : ({
      active: false,
      suggestions: [],
      saving: false,
      cursor: -1
    })
  // The view's cursor, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // Whether the place edit is open.
  readonly property bool editing: !!edit.active
  // The suggestion rows, or [].
  readonly property var suggestions: Array.isArray(edit.suggestions) ? edit.suggestions : []
  // The highlighted suggestion (the one Enter commits), or -1.
  readonly property int highlight: typeof edit.cursor === "number" && edit.cursor >= 0 && edit.cursor < suggestions.length ? edit.cursor : -1
  // The suggestions' keys joined, so an equal list rebuilt by the host
  // does not stamp the layout.
  readonly property string suggestionKeys: suggestions.map(function (s) {
    return s && typeof s.key === "string" ? s.key : ""
  }).join("\n")
  // Whether NEXT 24 H has anything to draw.
  readonly property bool hourlyShown: !!hourly.visible && !!hourlyPoints && Array.isArray(hourlyPoints.temp) && hourlyPoints.temp.length > 0

  // Emitted for every user action, NAME with its ARG:
  //   editPlace ({}): the place label was clicked (never while saving);
  //   query ({text}): typing changed the place field (never seeding it);
  //   pick ({index, key}): suggestion INDEX was clicked, KEY as the row
  //     held it (never when the row's key changed underneath);
  //   commit ({text, pick}): Enter in the place field: pick is the
  //     highlighted suggestion's {index, key}, or null with none or with
  //     an empty text (an empty commit is back to automatic);
  //   cancel ({}): Esc in the place field;
  //   step ({delta}): Up (-1) or Down (+1) in the place field, to move
  //     the highlighted suggestion;
  //   clearPlace ({}): the clear button beside the field was clicked;
  //   refresh ({}): the updated label was clicked;
  //   hover ({section, index, key}): the pointer really moved onto a
  //     control (through the gate); section is "place", "refresh", "clear"
  //     (index 0, key the section) or "suggestions" (key the row's).
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the controls without
  // rebuilding them.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven change so
  // a stale pointer sample never counts as a real move.
  function disarmPointer() {
    gate.reset()
  }

  // The cursor's section while active, or "".
  function cursorSection() {
    return dropdown.cursor.active ? String(dropdown.cursor.section || "") : ""
  }

  // The key of suggestion INDEX, or "".
  function keyAt(index) {
    var row = dropdown.suggestions[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  // Reports a real pointer move onto SECTION's control INDEX.
  function hoverAt(section, index) {
    dropdown.action("hover", {
      section: section,
      index: index,
      key: section === "suggestions" ? dropdown.keyAt(index) : section
    })
  }

  // Picks suggestion INDEX if its row still holds KEY; refused otherwise.
  function pickAt(index, key) {
    if (!key || dropdown.keyAt(index) !== key)
      return
    dropdown.action("pick", {
      index: index,
      key: key
    })
  }

  // Commits the field's TEXT with the highlighted suggestion, if any and
  // the text isn't empty.
  function commitText(text) {
    var value = String(text || "")
    var pick = null
    if (value.trim() !== "" && dropdown.highlight >= 0)
      pick = {
        index: dropdown.highlight,
        key: dropdown.keyAt(dropdown.highlight)
      }
    dropdown.action("commit", {
      text: value,
      pick: pick
    })
  }

  spacing: Style.space(10)
  onSuggestionKeysChanged: dropdown.noteLayoutChange()
  // The place edit and its clear button take the place label's spot (and
  // back) without the hero changing height: stamp, so a double-click on the
  // place can't land on the clear button.
  onEditingChanged: dropdown.noteLayoutChange()

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  WeatherHero {
    width: parent.width
    heroView: dropdown.hero
    rainSoon: dropdown.view && dropdown.view.rainSoon ? String(dropdown.view.rainSoon) : ""
    editing: dropdown.editing
    saving: !!dropdown.edit.saving
    editText: dropdown.editText
    cursorSection: dropdown.cursorSection()
    pointerGate: dropdown.pointerGate
    onHeightChanged: dropdown.noteLayoutChange()
    onPartShifted: dropdown.noteLayoutChange()
    onEditPlace: dropdown.action("editPlace", {})
    onRefresh: dropdown.action("refresh", {})
    onQuery: function (text) {
      dropdown.action("query", {
        text: text
      })
    }
    onCommit: function (text) {
      dropdown.commitText(text)
    }
    onCancel: dropdown.action("cancel", {})
    onStep: function (delta) {
      dropdown.action("step", {
        delta: delta
      })
    }
    onClearPlace: dropdown.action("clearPlace", {})
    onHovered: function (section) {
      dropdown.hoverAt(section, 0)
    }
  }
  WeatherSuggestions {
    objectName: "suggestionsSection"
    width: parent.width
    visible: dropdown.editing && !dropdown.edit.saving && dropdown.suggestions.length > 0
    rows: dropdown.suggestions
    highlight: dropdown.highlight
    // A search list: Enter commits the highlighted suggestion, so the
    // outline marks it whenever the list shows.
    cursorActive: true
    pointerGate: dropdown.pointerGate
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
    onPicked: function (index, key) {
      dropdown.pickAt(index, key)
    }
    onHovered: function (index) {
      dropdown.hoverAt("suggestions", index)
    }
  }
  Separator {
    visible: detailsSection.visible
  }
  WeatherDetails {
    id: detailsSection
    objectName: "detailsSection"
    width: parent.width
    visible: dropdown.details.length > 0
    cells: dropdown.details
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Separator {
    visible: hourlySection.visible
  }
  WeatherHourly {
    id: hourlySection
    objectName: "hourlySection"
    width: parent.width
    visible: dropdown.hourlyShown
    caption: dropdown.hourly.caption || ""
    labels: Array.isArray(dropdown.hourly.labels) ? dropdown.hourly.labels : []
    points: dropdown.hourlyPoints
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Separator {
    visible: airSection.visible
  }
  WeatherAir {
    id: airSection
    objectName: "airSection"
    width: parent.width
    visible: airSection.anyShown
    aqi: dropdown.air.aqi || ({
        visible: false
      })
    uv: dropdown.air.uv || ({
        visible: false
      })
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Separator {
    visible: daysSection.visible
  }
  WeatherDays {
    id: daysSection
    objectName: "daysSection"
    width: parent.width
    visible: dropdown.days.length > 0
    rows: dropdown.days
    onVisibleChanged: dropdown.noteLayoutChange()
    onHeightChanged: dropdown.noteLayoutChange()
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    topPadding: Style.space(4)
    text: dropdown.view && dropdown.view.keyHint ? dropdown.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Aranea.Typography.uiFamily
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
