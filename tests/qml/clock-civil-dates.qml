// Civil calendar dates stay consecutive across midnight DST transitions.
// Run with TZ=America/Santiago to exercise Qt's missing-midnight handling.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.clock/Model.js" as Model
import "plugins/araneadev.clock" as Clock

ShellRoot {
  Clock.Panel {
    id: clock
    viewYear: 2012
    viewMonth: 3
  }

  QmlTest {
    id: t
  }

  Component.onCompleted: {
    var days = Model.monthGrid(2026, 8, 1, "2026-09-06").reduce(function (all, week) {
      return all.concat(week.days)
    }, [])
    t.equal(days.length, 42, "calendar has six full weeks")
    for (var i = 1; i < days.length; i++) {
      var before = days[i - 1]
      var after = days[i]
      var delta = Date.UTC(after.year, after.month, after.day) - Date.UTC(before.year, before.month, before.day)
      t.equal(delta, 86400000, "civil date advances at cell " + i)
    }
    t.equal(days.filter(function (day) {
      return day.today
    }).length, 1, "today occurs exactly once")
    var target = Model.stepMonth(2026, 7, 1)
    t.equal(target.year, 2026, "month navigation retains year")
    t.equal(target.month, 8, "month navigation reaches September")
    t.equal(clock.viewDate.getMonth(), 3, "a missing first midnight still labels April")
    t.equal(clock.viewDate.getDate(), 1, "month label retains the first day")
    t.done()
  }
}
