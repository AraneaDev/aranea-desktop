// The Aranea Clock dropdown's month grid: a dim W column of ISO week
// numbers (its heading toggles the week start, with a tooltip naming the
// next start), the weekday headings and the day cells. Today is a mint
// diamond with a glow; days outside the viewed month are dim. The rows
// come from stock Model.js (weeks: [{week, days: [{key, day, inMonth}]}])
// as the host built them; the grid only draws them.
//
// The day cells live in a ListModel keyed by date: a rebuilt but equal
// weeks array (every minute's view) updates the cells in place, and today
// is a separate todayKey, so neither the clock ticking nor midnight ever
// rebuilds a cell. Only a different set of days (a month or week start
// change) does.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: grid

  // The view's week rows: [{week, days: [{key, day, inMonth}]}].
  property var weeks: []
  // The weekday headings in display order, e.g. ["MO", ..., "SU"].
  property var weekdays: []
  // Today's date key ("yyyy-MM-dd"), the one cell drawn as a diamond.
  property string todayKey: ""
  // The W heading's tooltip, e.g. "Start weeks on Sunday".
  property string weekStartLabel: ""
  // The dropdown's PointerMoveGate, carrying layoutChangedAt.
  property var pointerGate: null
  // How many week rows are shown.
  readonly property int weekCount: weekModel.count
  // The W column's width.
  readonly property real weekColumnWidth: Style.space(26)
  // Each day column's width: the rest split in seven.
  readonly property real cellWidth: Math.max(0, (width - weekColumnWidth) / 7)
  // Each row's height.
  readonly property real cellHeight: Style.space(26)

  // Emitted when the W heading is clicked (settled).
  signal toggleWeekStart
  // Emitted for a vertical wheel step over the grid, with its angle delta.
  signal wheel(real dy)
  // Emitted when the number of week rows changes (5 or 6), before the
  // grid has been laid out again.
  signal weekCountShifted

  // Brings the models in line with weeks: in place when the days are the
  // same (same keys in the same order), rebuilt otherwise.
  function sync() {
    var rows = Array.isArray(grid.weeks) ? grid.weeks : []
    var flat = []
    for (var w = 0; w < rows.length; w++) {
      var days = rows[w] && Array.isArray(rows[w].days) ? rows[w].days : []
      for (var d = 0; d < days.length; d++)
        flat.push({
          key: String(days[d].key || ""),
          day: Number(days[d].day) || 0,
          inMonth: !!days[d].inMonth
        })
    }
    var same = flat.length === dayModel.count
    for (var i = 0; same && i < flat.length; i++)
      same = dayModel.get(i).key === flat[i].key
    if (same) {
      for (var j = 0; j < flat.length; j++) {
        var cell = dayModel.get(j)
        if (cell.day !== flat[j].day)
          dayModel.setProperty(j, "day", flat[j].day)
        if (cell.inMonth !== flat[j].inMonth)
          dayModel.setProperty(j, "inMonth", flat[j].inMonth)
      }
    } else {
      dayModel.clear()
      for (var k = 0; k < flat.length; k++)
        dayModel.append(flat[k])
    }
    var before = weekModel.count
    for (var r = 0; r < rows.length; r++) {
      var week = Number(rows[r] && rows[r].week) || 0
      if (r < weekModel.count) {
        if (weekModel.get(r).week !== week)
          weekModel.setProperty(r, "week", week)
      } else {
        weekModel.append({
          week: week
        })
      }
    }
    if (weekModel.count > rows.length)
      weekModel.remove(rows.length, weekModel.count - rows.length)
    if (weekModel.count !== before)
      grid.weekCountShifted()
  }

  spacing: Style.space(4)
  onWeeksChanged: grid.sync()
  Component.onCompleted: grid.sync()

  ListModel {
    id: dayModel
  }
  ListModel {
    id: weekModel
  }

  Row {
    width: grid.width
    height: Style.space(18)

    ClockLink {
      objectName: "weekHeading"
      width: grid.weekColumnWidth
      height: parent.height
      text: "W"
      restColor: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
      bold: true
      letterSpacing: 1
      tooltipText: grid.weekStartLabel
      pointerGate: grid.pointerGate
      onClicked: grid.toggleWeekStart()
    }
    Repeater {
      model: grid.weekdays
      Text {
        required property var modelData
        objectName: "weekdayHeading"
        width: grid.cellWidth
        height: parent.height
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        text: String(modelData)
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1
      }
    }
  }
  Row {
    objectName: "clockGrid"
    width: grid.width

    Column {
      width: grid.weekColumnWidth
      Repeater {
        model: weekModel
        Text {
          required property int week
          objectName: "weekNumber"
          width: grid.weekColumnWidth
          height: grid.cellHeight
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
          text: String(week)
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
    Grid {
      columns: 7
      Repeater {
        model: dayModel
        Item {
          id: cell
          required property string key
          required property int day
          required property bool inMonth
          // Whether this cell is today.
          readonly property bool isToday: cell.key !== "" && cell.key === grid.todayKey

          objectName: "dayCell"
          width: grid.cellWidth
          height: grid.cellHeight

          Rectangle {
            // The diamond's glow: a wider, faint diamond behind it.
            anchors.centerIn: parent
            width: Style.space(26)
            height: width
            rotation: 45
            visible: cell.isToday
            color: Util.alpha(Aranea.DesignTokens.accent, 0.22)
          }
          Rectangle {
            objectName: "todayMarker"
            anchors.centerIn: parent
            width: Style.space(20)
            height: width
            rotation: 45
            visible: cell.isToday
            color: Aranea.DesignTokens.accent
          }
          Text {
            objectName: "dayText"
            anchors.centerIn: parent
            text: String(cell.day)
            opacity: cell.inMonth || cell.isToday ? 1 : 0.3
            color: cell.isToday ? Aranea.DesignTokens.background : Aranea.DesignTokens.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.bodySmall
            font.bold: cell.isToday
          }
        }
      }
    }
    WheelHandler {
      onWheel: function (event) {
        // A horizontal wheel or side-scroll reports y === 0 (stock).
        if (event.angleDelta.y !== 0)
          grid.wheel(event.angleDelta.y)
      }
    }
  }
}
