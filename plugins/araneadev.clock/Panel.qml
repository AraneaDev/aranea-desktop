// Aranea Clock (araneadev.clock, cloned from omarchy.clock): the calendar
// dropdown. Stock's root logic stays (month and year stepping, Back to
// today, the week start setting, the Memento Mori edit, persistSettings,
// the SystemClock rollover, the hostWidget / barIdentity owner contract,
// centerOnBar and open / close / toggle). Added here: the sun and moon
// (the weather location file, else one wttr.in lookup a day on open), the
// showcase stand-in place for README captures, and handleAction. The pure
// view, ClockDropdown, draws it in the shared keyboard frame; the sun and
// moon rules are ClockLogic.js functions, tested under Node.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "ClockLogic.js" as ClockLogic
import "../araneadev.shared" as Aranea

// The clock's calendar popup: a month grid with ISO week numbers.
//
// The grid is a read-out rather than a picker: today is the only marked
// day, and the only thing that moves is which month is on screen -
// chevrons, the scroll wheel, and the arrow keys all step it.
//
// BarWidget.qml owns the bar label and hands this panel the button to
// anchor against.
Panel {
  id: root
  moduleName: "omarchy.clock"
  ipcTarget: "omarchy.clock"
  manageIpc: false

  // The bar button to anchor the popup against, set by BarWidget.qml.
  property var anchorItem: null

  // The bar tracks the widget mounted in its slot - BarWidget.qml - not this
  // nested panel. Everything the bar identifies a panel by has to be that
  // widget: the popout coordinator (and with it the open-panel dot under the
  // pill) compares against `slot.activeItem`, and switchPanelFrom looks the
  // slot up the same way.
  property var hostWidget: null
  // The identity the bar's popout coordinator tracks: hostWidget when set,
  // else this panel itself.
  readonly property var barIdentity: hostWidget || root
  // The id the bar entry, the plugin shell and moduleWidgets know this
  // widget by: the host's moduleName, which the bar sets to the entry's id
  // ("araneadev.clock"), else this panel's own. moduleName itself stays
  // "omarchy.clock" for IPC.
  readonly property string entryId: hostWidget && hostWidget.moduleName ? String(hostWidget.moduleName) : root.moduleName

  // ---- Today. SystemClock keeps this honest across midnight so the
  //      highlight rolls over without the panel being reopened.
  property date today: new Date()
  // today's dateKey, so grid cells can mark it without comparing Date
  // objects.
  readonly property string todayKey: Model.keyForDate(today)

  // The month on screen. Stepping moves this and nothing else: the grid is
  // a read-out, not a picker, so there is no per-day cursor to keep in sync.
  property int viewYear: today.getFullYear()
  // The zero-based month on screen.
  property int viewMonth: today.getMonth()

  // The first day of the viewed month, as a Date.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1)
  // Whether the grid is showing today's own month (hides "Back to today").
  readonly property bool viewingCurrentMonth: viewYear === today.getFullYear() && viewMonth === today.getMonth()

  // Pinned to today, not to the month being browsed - stepping through the
  // calendar does not change how much of the year is gone.
  readonly property real yearDone: Model.yearProgress(today.getFullYear(), today.getMonth(), today.getDate())
  // yearDone as a rounded whole percent.
  readonly property int yearDonePercent: Model.yearProgressPercent(today.getFullYear(), today.getMonth(), today.getDate())

  // Memento mori, for anyone who goes looking: double-tapping the year bar
  // asks for a birth year and a life expectancy, and a second bar tracks one
  // against the other. A birth year rather than an age, so it keeps counting
  // on its own. Without one the bar stays hidden.
  readonly property int birthYear: Model.parseBirthYear(setting("birthYear", 0), today.getFullYear())
  // The age in whole years implied by birthYear, 0 when unset.
  readonly property int age: Model.ageFromBirthYear(birthYear, today.getFullYear())
  // The configured (or default) life expectancy in years.
  readonly property int lifeExpectancy: Model.parseLifeExpectancy(setting("lifeExpectancy", 0))
  // The fraction of lifeExpectancy reached at the current age.
  readonly property real lifeDone: Model.lifeProgress(age, lifeExpectancy)
  // lifeDone as a rounded whole percent.
  readonly property int lifeDonePercent: Model.lifeProgressPercent(age, lifeExpectancy)
  // True while the birth year / life expectancy fields are open for editing.
  property bool editingLife: false

  // Unset falls through to the locale's own first day, so a fresh install
  // starts out matching the rest of the desktop rather than a hardcoded
  // convention. Clicking the grid's "W" heading writes the choice back to
  // shell.json.
  readonly property int weekStart: Model.normalizedWeekStart(setting("weekStartDay", null), Qt.locale().firstDayOfWeek)
  // The interface is English throughout, so day names are not taken from the
  // system locale. Where the week starts still is: that is a regional
  // convention rather than a translation, and it stays overridable above.
  readonly property var labelLocale: Qt.locale("en_US")
  // The day name the "W" heading's tooltip offers to switch to.
  readonly property string nextWeekStartLabel: labelLocale.dayName(Model.toggledWeekStart(weekStart), Locale.LongFormat)
  // The seven weekday indices in header/column order for weekStart.
  readonly property var weekdays: Model.weekdayOrder(weekStart)
  // The six-week grid for the viewed month.
  readonly property var weeks: Model.monthGrid(viewYear, viewMonth, weekStart, todayKey)

  // The month grid's rows for the view: stock's weeks without their
  // trailing all-next-month rows (5 or 6 weeks), each day trimmed to the
  // key, the day number and whether it is in the viewed month. Today is
  // the separate todayKey, so the cells never rebuild for it.
  readonly property var gridWeeks: root.weeks.filter(function (w) {
    return w.days.some(function (d) {
      return d.inMonth
    })
  }).map(function (w) {
    return {
      week: w.week,
      days: w.days.map(function (d) {
        return {
          key: d.key,
          day: d.day,
          inMonth: d.inMonth
        }
      })
    }
  })

  // The life fields' texts: seeded by startEditingLife, replaced by the
  // texts a lifeCommit carries, and read by commitLife.
  property string lifeBornText: ""
  // The live-to field's text, as lifeBornText.
  property string lifeLiveToText: ""

  // ---- Sun and moon.
  // The weather location (stock weather's state file), only when it has
  // coordinates; null otherwise, which lets the wttr.in lookup run.
  property var configuredPlace: null
  // The place wttr.in resolved today ({name, lat, lon}), kept for the
  // session; null until a lookup succeeds.
  property var wttrPlace: null
  // The day key ("yyyy-MM-dd") of the current or last successful wttr.in
  // lookup (or of a place adopted from another monitor's instance); ""
  // again after a failed or cancelled lookup, so the next open retries.
  property string areaFetchDay: ""
  // The day key wttrPlace was resolved on, which the other monitors'
  // instances read before looking it up themselves (ClockLogic.areaPlan).
  property string wttrPlaceDay: ""
  // The README capture's stand-in place (the showcase IPC method); null
  // outside a capture, and cleared whenever the dropdown opens or closes.
  property var showcasePlace: null
  // The time the sun arc and the moon are drawn for: set on open and by
  // the minute timer while open.
  property date skyNow: new Date()
  // The place the sun is computed for: the stand-in, else the configured
  // location, else wttr.in's.
  readonly property var skyPlace: showcasePlace || configuredPlace || wttrPlace
  // Today's sun times at skyPlace (ClockLogic.sunTimes), or null without a
  // place.
  readonly property var sunToday: skyPlace && skyPlace.lat !== null ? ClockLogic.sunTimes(skyPlace.lat, skyPlace.lon, today.getFullYear(), today.getMonth() + 1, today.getDate(), -today.getTimezoneOffset()) : null
  // The view's sky part: the place caption, the sun (hidden without a
  // place) and the moon (always).
  readonly property var skyView: {
    var sun = root.sunToday
    var sunView = {
      visible: false
    }
    if (sun) {
      var polar = sun.polar
      // sunArcPosition reads a polar day as night, so a polar sun takes
      // its state from polar instead.
      var arc = polar !== "" ? {
        t: 0,
        night: polar === "night"
      } : ClockLogic.sunArcPosition(root.skyNow.getHours() * 60 + root.skyNow.getMinutes(), sun.sunrise, sun.sunset)
      sunView = {
        visible: true,
        sunrise: polar !== "" ? "" : ClockLogic.formatClock(sun.sunrise),
        sunset: polar !== "" ? "" : ClockLogic.formatClock(sun.sunset),
        daylight: polar !== "" ? "" : ClockLogic.daylightText(sun.sunrise, sun.sunset),
        arcT: arc.t,
        night: arc.night,
        polar: polar
      }
    }
    var moon = ClockLogic.moonPhase(root.skyNow.getTime())
    return {
      visible: true,
      place: root.showcasePlace ? root.showcasePlace.name : ClockLogic.placeCaption(root.configuredPlace, root.wttrPlace),
      sun: sunView,
      moon: {
        glyph: ClockLogic.moonGlyph(moon.index),
        name: moon.name,
        illumination: moon.illumination
      }
    }
  }

  // The plain view object ClockDropdown draws (see its view property).
  readonly property var clockView: ({
      title: root.today.toLocaleDateString(root.labelLocale, "dddd d MMMM"),
      subtitle: Qt.formatTime(clock.date, "HH:mm") + " · Week " + Model.isoWeek(root.today.getFullYear(), root.today.getMonth(), root.today.getDate()),
      monthLabel: root.viewDate.toLocaleDateString(root.labelLocale, "MMMM yyyy"),
      viewingCurrentMonth: root.viewingCurrentMonth,
      weekdays: root.weekdays.map(function (d) {
        return root.weekdayLabel(d).slice(0, 2)
      }),
      weeks: root.gridWeeks,
      weekStartLabel: "Start weeks on " + root.nextWeekStartLabel,
      year: {
        percent: root.yearDonePercent
      },
      life: {
        visible: root.birthYear > 0,
        percent: root.lifeDonePercent,
        born: root.birthYear,
        liveTo: root.lifeExpectancy,
        editing: root.editingLife
      },
      sky: root.skyView,
      keyHint: "←→ month · ↑↓ year · t today · tab next"
    })
  // Refreshes to today and reveals the popup.
  function open() {
    refresh()
    root.controller.show()
    // Set after showing, not before: showing hands the popout coordinator
    // over, which closes whichever panel was open, and that close clears the
    // shared flag. Deferring means the panel taking over always wins, while
    // a handoff to a panel that does not manage the flag still leaves it
    // cleared rather than stuck on.
    Qt.callLater(function () {
      if (root.opened)
        setCenterHoverRevealSuppressed(true)
    })
  }

  // Hides the popup and cancels any in-progress life-field edit.
  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife)
      root.cancelEditingLife()
    root.controller.hide()
  }

  // Opens the popup if closed, closes it if open.
  function toggle() {
    if (root.opened)
      root.close()
    else
      root.open()
  }

  // Hands focus to the bar's other open dropdown, if any, for Tab cycling.
  function switchPanel(direction) {
    // qmllint disable missing-property
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    // qmllint enable missing-property
    return false
  }

  // Summoning by hotkey moves no pointer, so a hover the bar was still
  // holding must not keep the center indicators revealed behind the panel.
  function setCenterHoverRevealSuppressed(value) {
    // qmllint disable missing-property
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else
    // qmllint enable missing-property
    if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
  }

  // Re-reads today's date and snaps the grid back to it.
  function refresh() {
    root.today = new Date()
    root.goToToday()
  }

  // Snaps the viewed month back to today's.
  function goToToday() {
    root.viewYear = today.getFullYear()
    root.viewMonth = today.getMonth()
  }

  // Steps the viewed month by delta months (negative steps back).
  function moveMonth(delta) {
    var next = Model.stepMonth(viewYear, viewMonth, delta)
    root.viewYear = next.year
    root.viewMonth = next.month
  }

  // Steps the viewed month by delta years.
  function moveYear(delta) {
    moveMonth(delta * 12)
  }

  // Applied locally first so the panel redraws on the click itself; the
  // shell.json write comes back through the bar as the same value. With no
  // writable entry (the widget is not in the layout) it stays a session-only
  // preference rather than doing nothing. The host widget builds its own
  // entry when the label format is cycled, so it has to be kept in step or
  // it would write this key straight back out from a stale copy.
  // The write goes under entryId (the bar entry's id): the plugin shell
  // drops a write under any other id.
  function persistSettings(values) {
    var write = ClockLogic.persistEntry(root.entryId, root.moduleName, root.settings, values)
    root.settings = write.entry
    if (root.hostWidget && "settings" in root.hostWidget)
      root.hostWidget.settings = write.entry
    // qmllint disable missing-property
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(write.id, write.entry)
    // qmllint enable missing-property
  }

  // Persists a new week start, no-op when it matches the current one.
  function setWeekStart(day) {
    var next = Model.normalizedWeekStart(day, root.weekStart)
    if (next === root.weekStart)
      return
    persistSettings({
      weekStartDay: Model.weekStartSettingName(next)
    })
  }

  // Opens the birth year / life expectancy fields, pre-filled and focused
  // (the view focuses the born field and selects its text).
  function startEditingLife() {
    root.lifeBornText = root.birthYear > 0 ? String(root.birthYear) : ""
    root.lifeLiveToText = String(root.lifeExpectancy)
    root.editingLife = true
  }

  // Closes the life fields without saving and returns focus to the grid.
  function cancelEditingLife() {
    root.editingLife = false
    Qt.callLater(function () {
      if (panel.focusTarget)
        panel.focusTarget.forceActiveFocus()
    })
  }

  // Double-tapping the life bar puts it away again. The expectancy stays in
  // the config so setting a birth year again brings your own number back
  // rather than the default.
  function clearLife() {
    if (root.birthYear <= 0)
      return
    persistSettings({
      birthYear: 0
    })
  }

  // Saves the edited birth year and life expectancy, then closes the fields.
  function commitLife() {
    var born = Model.parseBirthYear(root.lifeBornText, today.getFullYear())
    var span = Model.parseLifeExpectancy(root.lifeLiveToText)
    if (born !== root.birthYear || span !== root.lifeExpectancy)
      persistSettings({
        birthYear: born,
        lifeExpectancy: span
      })
    cancelEditingLife()
  }

  // Flips the week start between the two conventions and persists it.
  function toggleWeekStart() {
    setWeekStart(Model.toggledWeekStart(root.weekStart))
  }

  // English short day names, matching the rest of the interface.
  function weekdayLabel(weekday) {
    return String(labelLocale.dayName(weekday, Locale.ShortFormat)).toUpperCase()
  }

  // Runs a ClockDropdown action (see its action signal) through stock's
  // functions, as ClockLogic.actionStep maps it.
  function handleAction(name, arg) {
    var step = ClockLogic.actionStep(name, arg, root.editingLife)
    if (step.op === "moveMonth")
      root.moveMonth(step.delta)
    else if (step.op === "today")
      root.goToToday()
    else if (step.op === "toggleWeekStart")
      root.toggleWeekStart()
    else if (step.op === "clearLife")
      root.clearLife()
    else if (step.op === "startEditingLife")
      root.startEditingLife()
    else if (step.op === "commitLife") {
      root.lifeBornText = step.born
      root.lifeLiveToText = step.liveTo
      root.commitLife()
    } else if (step.op === "cancelEditingLife")
      root.cancelEditingLife()
  }

  // Reads the weather location file's text into configuredPlace (only a
  // place with coordinates counts; anything else falls back to wttr.in).
  function applyLocationText(text) {
    var place = ClockLogic.parseWeatherLocation(text)
    root.configuredPlace = place && place.lat !== null ? place : null
  }

  // The other monitors' instances' wttr.in places ({placeDay, place}):
  // each bar surface hosts its own clock, and so its own panel.
  function peerAreas() {
    // qmllint disable missing-property
    var hosts = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.entryId) : []
    var areas = []
    for (var i = 0; i < hosts.length; i++) {
      var peer = hosts[i] ? hosts[i].clockPanel : null
      if (peer && peer !== root)
        areas.push({
          placeDay: String(peer.wttrPlaceDay || ""),
          place: peer.wttrPlace || null
        })
    }
    // qmllint enable missing-property
    return areas
  }

  // On open, as ClockLogic.areaPlan decides across every monitor: adopts
  // the place another instance looked up today, else starts today's
  // lookup (open, no configured location, not yet looked up today).
  function maybeFetchArea() {
    var day = Model.keyForDate(new Date())
    if (areaProc.running)
      return
    var plan = ClockLogic.areaPlan(root.configuredPlace, root.areaFetchDay, root.peerAreas(), day, root.opened)
    if (plan.adopt) {
      root.wttrPlace = plan.adopt
      root.wttrPlaceDay = day
      root.areaFetchDay = day
    } else if (plan.fetch) {
      root.areaFetchDay = day
      areaProc.running = true
    }
  }

  // Takes a wttr.in response: the place on success, else clears the day
  // key so the next open tries again (no retry loop).
  function applyArea(text) {
    var place = ClockLogic.parseWttrArea(text)
    if (place) {
      root.wttrPlace = place
      root.wttrPlaceDay = root.areaFetchDay
    } else
      root.areaFetchDay = ""
  }

  // The showcase IPC method (forwarded by BarWidget): PLACEJSON, a
  // {"name", "latitude", "longitude"} object, stands in for the real place
  // until the dropdown closes. "closed" while closed, "invalid" for a bad
  // place. Display only.
  function showcase(placeJson) {
    var call = ClockLogic.showcaseCall(root.opened, placeJson)
    if (call.place !== null)
      root.showcasePlace = call.place
    return call.answer
  }

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
    onDateChanged: {
      if (Model.keyForDate(clock.date) === String(root.todayKey))
        return
      var followToday = root.viewingCurrentMonth
      root.today = clock.date
      if (followToday)
        root.goToToday()
    }
  }

  // The stand-in place never carries over into an open or past a close; an
  // open redraws the sky for now and may start today's lookup, and a close
  // stops a lookup still running and clears its day key, so the next open
  // tries again.
  Connections {
    target: root
    function onOpenedChanged() {
      root.showcasePlace = null
      if (root.opened) {
        root.skyNow = new Date()
        locationFile.reload()
        root.maybeFetchArea()
      } else if (areaProc.running) {
        areaProc.running = false
        root.areaFetchDay = ""
      }
    }
  }

  // Stock weather's location file, watched so an edit takes effect live.
  FileView {
    id: locationFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: locationFile.reload()
    onLoaded: root.applyLocationText(locationFile.text())
    onLoadFailed: root.applyLocationText("")
  }

  // The once-a-day place lookup, only on open and only without a
  // configured location (maybeFetchArea).
  Process {
    id: areaProc
    command: ["curl", "-fsS", "--max-time", "8", "https://wttr.in/?format=j1"]
    stdout: StdioCollector {
      id: areaOut
      waitForEnd: true
      onStreamFinished: root.applyArea(areaOut.text)
    }
  }

  // Moves the sun arc's dot along once a minute while open.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.skyNow = new Date()
  }

  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    blocked: root.editingLife
    // Wider than the other dropdowns (380): the sun and moon pairs share a
    // row, and the longest moon line ("Waxing crescent · 100%") must leave
    // room for its "Moon" label.
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      if (dx !== 0)
        root.moveMonth(dx)
      if (dy !== 0)
        root.moveYear(dy)
    }
    onActivateRequested: {
      dropdown.disarmPointer()
      root.goToToday()
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      if (t === "[")
        root.moveMonth(-1)
      else if (t === "]")
        root.moveMonth(1)
      else if (t === "{")
        root.moveYear(-1)
      else if (t === "}")
        root.moveYear(1)
      else if (t === "t" || t === "T")
        root.goToToday()
      else if (t === "w" || t === "W")
        root.toggleWeekStart()
    }

    Item {
      anchors.fill: parent
      clip: true

      ClockDropdown {
        id: dropdown
        width: parent.width
        view: root.clockView
        todayKey: root.todayKey
        bornText: root.lifeBornText
        liveToText: root.lifeLiveToText
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
