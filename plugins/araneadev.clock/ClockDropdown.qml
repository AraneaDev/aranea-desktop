// The Aranea Clock dropdown's view: the header (today's date, the time and
// ISO week, and a trailing previous / month / next), the month grid with
// ISO week numbers and today's diamond, the SUN & MOON section, the YEAR
// and LIFE strands with the life edit row, Back to today and the week
// start label, and the key hint. Drawn from one plain view object
// (Panel.clockView) plus todayKey, bornText and liveToText kept out of it,
// and reporting every user action through a single action signal. No
// clocks, settings or processes here: tests drive it with fixtures.
//
// The calendar is a read-out with no cursor, so nothing draws an outline;
// the controls are pointer-only (the life fields keep their own focus).
// The day cells are keyed by date and today is todayKey, so neither the
// minute nor midnight rebuilds a cell. Any section changing height or
// visibility, a month changing the week count, and Back to today appearing
// or going stamp layoutChangedAt; a click within 300 ms of that, or of its
// control being built, is ignored unless the pointer has really moved onto
// it since.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Column {
  id: dropdown

  // View state built by Panel.clockView: {title, subtitle, monthLabel,
  // viewingCurrentMonth, weekdays: [label], weeks: [{week, days: [{key,
  // day, inMonth}]}] (stock Model.monthGrid's rows), weekStartLabel (e.g.
  // "Start weeks on Sunday"), year: {percent}, life: {visible, percent,
  // born, liveTo, editing}, sky: {visible, place, sun: {visible, sunrise,
  // sunset, daylight, arcT, night, polar}, moon: {glyph, name,
  // illumination}}, keyHint}. The days carry no today flag.
  property var view: ({})
  // Today's date key ("yyyy-MM-dd"): the one cell drawn as a diamond.
  property string todayKey: ""
  // The born field's text while editing the life bar.
  property string bornText: ""
  // The live-to field's text while editing the life bar.
  property string liveToText: ""
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0
  // Filters synthetic hover from controls moving under a still pointer,
  // and carries layoutChangedAt to the controls that settle clicks.
  readonly property alias pointerGate: gate
  // The view's year part, or an empty one.
  readonly property var year: view && view.year ? view.year : ({})
  // The view's life part, or a hidden one.
  readonly property var life: view && view.life ? view.life : ({
      visible: false
    })
  // The view's sky part, or a hidden one.
  readonly property var sky: view && view.sky ? view.sky : ({
      visible: false
    })
  // Whether the view is on today's month: Back to today shows only when it
  // is not, and its appearing or going stamps the layout.
  readonly property bool viewingCurrentMonth: !view || view.viewingCurrentMonth !== false
  // Whether the sun and moon section has anything to show.
  readonly property bool skyShown: !!sky.visible && (!!(sky.sun && sky.sun.visible) || !!(sky.moon && sky.moon.name))

  // Emitted for every user action, NAME with its ARG:
  //   prevMonth ({}), nextMonth ({}): a chevron was clicked;
  //   today ({}): Back to today was clicked;
  //   toggleWeekStart ({}): the W heading or the week start label was
  //     clicked;
  //   wheel ({dy}): a vertical wheel step over the grid, dy the angle
  //     delta as Qt reports it (positive is up: stock steps back a month);
  //   editLife ({clear}): a double-click on the year bar (clear false:
  //     start editing) or on the life bar (clear true: clear it);
  //   lifeCommit ({born, liveTo}): Enter in a life field, with both
  //     fields' texts unparsed;
  //   lifeCancel ({}): Esc in a life field.
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

  spacing: Style.space(10)

  onViewingCurrentMonthChanged: dropdown.noteLayoutChange()

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  Aranea.DropdownHeader {
    refined: true
    objectName: "clockHeader"
    width: parent.width
    glyph: String.fromCodePoint(0xf00ed)
    title: dropdown.view && dropdown.view.title ? dropdown.view.title : ""
    caption: dropdown.view && dropdown.view.subtitle ? dropdown.view.subtitle : ""
    onHeightChanged: dropdown.noteLayoutChange()

    Row {
      spacing: Style.space(6)

      ClockLink {
        objectName: "prevMonth"
        fontFamily: Aranea.Typography.iconFamily
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        text: String.fromCodePoint(0xf0141)
        pixelSize: Style.font.body
        tooltipText: "Previous month"
        pointerGate: dropdown.pointerGate
        onClicked: dropdown.action("prevMonth", {})
      }
      Text {
        objectName: "monthLabel"
        anchors.verticalCenter: parent.verticalCenter
        // Fixed width, so the chevrons hold still from May to September.
        width: Math.ceil(monthMetrics.advanceWidth)
        horizontalAlignment: Text.AlignHCenter
        text: dropdown.view && dropdown.view.monthLabel ? dropdown.view.monthLabel : ""
        color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption

        TextMetrics {
          id: monthMetrics
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.caption
          text: "September 0000"
        }
      }
      ClockLink {
        objectName: "nextMonth"
        fontFamily: Aranea.Typography.iconFamily
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(18)
        text: String.fromCodePoint(0xf0142)
        pixelSize: Style.font.body
        tooltipText: "Next month"
        pointerGate: dropdown.pointerGate
        onClicked: dropdown.action("nextMonth", {})
      }
    }
  }
  Separator {}
  ClockGrid {
    width: parent.width
    weeks: dropdown.view && Array.isArray(dropdown.view.weeks) ? dropdown.view.weeks : []
    weekdays: dropdown.view && Array.isArray(dropdown.view.weekdays) ? dropdown.view.weekdays : []
    todayKey: dropdown.todayKey
    weekStartLabel: dropdown.view && dropdown.view.weekStartLabel ? dropdown.view.weekStartLabel : ""
    pointerGate: dropdown.pointerGate
    onHeightChanged: dropdown.noteLayoutChange()
    onWeekCountShifted: dropdown.noteLayoutChange()
    onToggleWeekStart: dropdown.action("toggleWeekStart", {})
    onWheel: function (dy) {
      dropdown.action("wheel", {
        dy: dy
      })
    }
  }
  Separator {
    visible: skySection.visible
  }
  ClockSky {
    id: skySection
    objectName: "skySection"
    width: parent.width
    visible: dropdown.skyShown
    skyView: dropdown.sky
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()
  }
  Separator {}
  ClockLife {
    width: parent.width
    yearPercent: Number(dropdown.year.percent) || 0
    lifeVisible: !!dropdown.life.visible
    lifePercent: Number(dropdown.life.percent) || 0
    editing: !!dropdown.life.editing
    bornText: dropdown.bornText
    liveToText: dropdown.liveToText
    pointerGate: dropdown.pointerGate
    onHeightChanged: dropdown.noteLayoutChange()
    onPartShifted: dropdown.noteLayoutChange()
    onEditLife: function (clear) {
      dropdown.action("editLife", {
        clear: clear
      })
    }
    onCommit: function (born, liveTo) {
      dropdown.action("lifeCommit", {
        born: born,
        liveTo: liveTo
      })
    }
    onCancel: dropdown.action("lifeCancel", {})
  }
  Item {
    width: parent.width
    implicitHeight: Math.max(backToToday.implicitHeight, weekStartLabel.implicitHeight)

    ClockLink {
      id: backToToday
      objectName: "backToToday"
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      visible: !dropdown.viewingCurrentMonth
      text: "Back to today"
      pointerGate: dropdown.pointerGate
      onClicked: dropdown.action("today", {})
    }
    ClockLink {
      id: weekStartLabel
      objectName: "weekStartLabel"
      // "Start weeks on Sunday" reads "W: start weeks on Sunday".
      readonly property string label: dropdown.view && dropdown.view.weekStartLabel ? String(dropdown.view.weekStartLabel) : ""
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      visible: weekStartLabel.label !== ""
      text: "W: " + weekStartLabel.label.charAt(0).toLowerCase() + weekStartLabel.label.slice(1)
      pointerGate: dropdown.pointerGate
      onClicked: dropdown.action("toggleWeekStart", {})
    }
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    text: dropdown.view && dropdown.view.keyHint ? dropdown.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
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
