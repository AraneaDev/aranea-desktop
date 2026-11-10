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

  Clock.WallClock {
    id: wallClock
    step: 1000
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
    var minuteClock = t.childrenOf(clock).filter(function (child) {
      return child.step === 60000
    })[0]
    t.check(!!minuteClock, "calendar uses the epoch-aligned minute clock")
    clock.today = new Date(2026, 8, 30, 23, 59)
    clock.goToToday()
    minuteClock.date = new Date(2026, 9, 1, 0, 0)
    t.equal(clock.todayKey, "2026-10-01", "minute consumer rolls over midnight")
    t.equal(clock.viewMonth, 9, "following today rolls to the new month")
    clock.moveMonth(-3)
    minuteClock.date = new Date(2026, 9, 2, 0, 0)
    t.equal(clock.todayKey, "2026-10-02", "browsing another month still updates today")
    t.equal(clock.viewMonth, 6, "midnight preserves the browsed month")
    clock.refresh()
    t.equal(clock.todayKey, Model.keyForDate(new Date()), "explicit panel refresh rereads the current day")
    wallClock.date = new Date(0)
    wallClock.refresh()
    t.check(Math.abs(wallClock.date.getTime() - Date.now()) < 1000, "explicit refresh reads the current epoch")
    t.check(wallClock.running && wallClock.interval >= 1 && wallClock.interval <= 1000, "wall clock rearms within its epoch step")
    t.done()
  }
}
