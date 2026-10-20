// Clock owns one anchored Calendar, World Clock and Weather keyboard popup.
// Calendar retains its existing model and actions; optional controllers and views
// load in embedded mode before construction and share this single native frame.
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

  // Selected page; only its controller may run an open lifecycle.
  property string activePage: "calendar"
  // Embedded optional controllers, also exposed by the mounted clock widget.
  readonly property var weatherPanel: weatherLoader.item
  // Embedded world-clock controller, null when unavailable.
  readonly property var worldClockPanel: worldLoader.item
  // Uniform active controller interface for shared keyboard routing.
  readonly property var activePageController: activePage === "weather" ? weatherPanel : activePage === "worldclock" ? worldClockPanel : root
  // Optional hosted views load independently so Calendar survives missing plugins.
  readonly property var worldDropdown: worldViewLoader.item
  // Weather's hosted view, null until the optional plugin is ready.
  readonly property var weatherDropdown: weatherViewLoader.item
  // Calendar-only work must stop when another page owns the popup.
  readonly property bool calendarActive: opened && activePage === "calendar"

  // Cancel the outgoing page before selecting a valid available page.
  function selectPage(page) {
    if (page !== "calendar" && page !== "worldclock" && page !== "weather")
      return false
    if ((page === "worldclock" && !worldClockPanel) || (page === "weather" && !weatherPanel))
      return false
    if (page === activePage)
      return true
    disarmPointer()
    if (weatherPanel)
      weatherPanel.deactivateEmbedded()
    if (worldClockPanel)
      worldClockPanel.deactivateEmbedded()
    if (editingLife)
      cancelEditingLife()
    activePage = page
    viewport.contentY = 0
    if (opened)
      activatePage()
    focusPage(page)
    return true
  }

  // Start only the selected page without claiming another native surface.
  function activatePage() {
    if (activePage === "calendar") {
      root.refresh()
      root.skyNow = new Date()
      locationFile.reload()
      root.maybeFetchArea()
    } else if (activePageController)
      activePageController.activateEmbedded()
  }

  // A queued focus request belongs to the same still-open page only.
  function focusPage(page) {
    Qt.callLater(function () {
      if (root.opened && root.activePage === page && panel.focusTarget)
        panel.focusTarget.forceActiveFocus()
    })
  }

  // Open a named section directly, without briefly activating Calendar.
  function openSection(page) {
    var wasOpen = opened
    var changed = page !== activePage
    if (!selectPage(page))
      return false
    if (!opened)
      root.controller.show()
    if (!wasOpen || !changed)
      activatePage()
    Qt.callLater(function () {
      if (root.opened)
        setCenterHoverRevealSuppressed(true)
    })
    return true
  }

  // Toggle only this section; another active page counts as closed.
  function toggleSection(page) {
    if (isSectionOpen(page))
      close()
    else
      openSection(page)
  }

  // Section-specific state for trusted aliases and legacy IPC.
  function isSectionOpen(page) {
    return opened && activePage === page
  }

  // Merge into the latest whole own-entry settings, retaining other pages.
  function persistSection(page, values) {
    var key = page === "worldclock" ? "worldClock" : page === "weather" ? "weather" : ""
    if (!key)
      return false
    var current = hostWidget ? hostWidget.settings : settings
    var nested = {}, patch = {}
    var previous = current && current[key] ? current[key] : {}
    for (let name in previous)
      nested[name] = previous[name]
    for (let field in values)
      nested[field] = values[field]
    patch[key] = nested
    persistSettings(patch)
    return true
  }

  // Disarm the current page before keyboard input or a page handoff.
  function disarmPointer() {
    if (activePage === "calendar")
      dropdown.disarmPointer()
    else if (activePageController)
      activePageController.disarmPointer()
  }

  // Calendar navigation keeps its original month/year behavior.
  function navigateKeyboard(dx, dy) {
    disarmPointer()
    if (dx !== 0)
      moveMonth(dx)
    if (dy !== 0)
      moveYear(dy)
  }

  // Calendar activation returns to today.
  function activateKeyboard() {
    disarmPointer()
    goToToday()
  }

  // Calendar has no deletion action; other pages implement their own.
  function deleteKeyboard() {
  }

  // Existing Calendar shortcuts, routed only while it is selected.
  function textKeyboard(text) {
    disarmPointer()
    if (text === "[")
      moveMonth(-1)
    else if (text === "]")
      moveMonth(1)
    else if (text === "{")
      moveYear(-1)
    else if (text === "}")
      moveYear(1)
    else if (text === "t" || text === "T")
      goToToday()
    else if (text === "w" || text === "W")
      toggleWeekStart()
  }

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

  // Local noon keeps the month label correct when DST removes its first midnight.
  readonly property date viewDate: new Date(viewYear, viewMonth, 1, 12)
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
      let polar = sun.polar
      // sunArcPosition reads a polar day as night, so a polar sun takes
      // its state from polar instead.
      let arc = polar !== "" ? {
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
      keyHint: ClockLogic.keyHint()
    })
  // Refreshes to today and reveals the popup.
  function open() {
    openSection("calendar")
  }

  // Hides the popup and cancels any in-progress life-field edit.
  function close() {
    setCenterHoverRevealSuppressed(false)
    // Dismissing the panel mid-edit would otherwise leave the inputs up,
    // waiting behind a closed popup for the next time it opens.
    if (root.editingLife)
      root.cancelEditingLife()
    if (weatherPanel)
      weatherPanel.deactivateEmbedded()
    if (worldClockPanel)
      worldClockPanel.deactivateEmbedded()
    root.disarmPointer()
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
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
    // qmllint enable missing-property
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
    var write = ClockLogic.persistEntry(root.entryId, root.moduleName, root.hostWidget ? root.hostWidget.settings : root.settings, values)
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
      if (root.calendarActive && panel.focusTarget)
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
    for (let i = 0; i < hosts.length; i++) {
      let peer = hosts[i] ? hosts[i].clockPanel : null
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
    var plan = ClockLogic.areaPlan(root.configuredPlace, root.areaFetchDay, root.peerAreas(), day, root.calendarActive)
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
    function onCalendarActiveChanged() {
      root.showcasePlace = null
      if (root.calendarActive) {
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
    running: root.calendarActive
    onTriggered: root.skyNow = new Date()
  }

  // Initial properties prevent even transient standalone windows or polling.
  Loader {
    id: worldLoader
    Component.onCompleted: setSource(Qt.resolvedUrl("../araneadev.worldclock/Panel.qml"), {
      embedded: true,
      embeddingHost: root,
      bar: Qt.binding(function () {
        return root.bar
      }),
      hostWidget: Qt.binding(function () {
        return root.hostWidget
      }),
      settings: Qt.binding(function () {
        return root.settings.worldClock || {}
      }),
      hostedDropdown: Qt.binding(function () {
        return root.worldDropdown
      }),
      hostedFocusTarget: Qt.binding(function () {
        return panel.focusTarget
      })
    })
  }
  Loader {
    id: weatherLoader
    Component.onCompleted: setSource(Qt.resolvedUrl("../araneadev.weather/Panel.qml"), {
      embedded: true,
      embeddingHost: root,
      bar: Qt.binding(function () {
        return root.bar
      }),
      hostWidget: Qt.binding(function () {
        return root.hostWidget
      }),
      settings: Qt.binding(function () {
        return root.settings.weather || {}
      }),
      hostedDropdown: Qt.binding(function () {
        return root.weatherDropdown
      }),
      hostedFocusTarget: Qt.binding(function () {
        return panel.focusTarget
      })
    })
  }

  Aranea.KeyboardPanelFrame {
    id: panel
    objectName: "clockFrame"
    refined: true
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: false
    blocked: root.activePage === "calendar" ? root.editingLife : root.activePage === "worldclock" ? !!(root.worldClockPanel && root.worldClockPanel.adding) : !!(root.weatherPanel && root.weatherPanel.editingLocation && !root.weatherPanel.savingLocation) || weatherPreferences.editing
    contentWidth: panel.fittedContentWidth(Style.space(440))
    contentHeight: panel.fittedContentHeight(tabs.implicitHeight + Style.space(12) + (root.activePage === "worldclock" ? (root.worldDropdown ? root.worldDropdown.implicitHeight : 0) : root.activePage === "weather" ? weatherPage.implicitHeight : dropdown.implicitHeight))
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      root.disarmPointer()
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      if (root.activePageController)
        root.activePageController.navigateKeyboard(dx, dy)
    }
    onActivateRequested: if (root.activePageController)
      root.activePageController.activateKeyboard()
    onDeleteRequested: if (root.activePageController)
      root.activePageController.deleteKeyboard()
    onTextKey: function (text) {
      if (root.activePageController)
        root.activePageController.textKeyboard(text)
    }

    Item {
      anchors.fill: parent
      clip: true
      ClockTabs {
        id: tabs
        width: parent.width
        page: root.activePage
        worldClockAvailable: root.worldClockPanel !== null
        weatherAvailable: root.weatherPanel !== null
        onPageRequested: function (page) {
          root.selectPage(page)
        }
      }
      Flickable {
        id: viewport
        anchors.top: tabs.bottom
        anchors.topMargin: Style.space(12)
        anchors.bottom: parent.bottom
        width: parent.width
        contentWidth: width
        contentHeight: root.activePage === "worldclock" ? (root.worldDropdown ? root.worldDropdown.implicitHeight : 0) : root.activePage === "weather" ? weatherPage.implicitHeight : dropdown.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        // Keep long lists and the inline city editor within the fitted viewport.
        function reveal(top, rowHeight) {
          if (top < contentY)
            contentY = Math.max(0, top)
          else if (top + rowHeight > contentY + height)
            contentY = Math.max(0, Math.min(contentHeight - height, top + rowHeight - height))
        }
        onHeightChanged: Qt.callLater(function () {
          if (root.isSectionOpen("worldclock") && root.worldDropdown)
            root.worldDropdown.revealCurrent()
        })
        ClockDropdown {
          id: dropdown
          visible: root.calendarActive
          width: viewport.width
          view: root.clockView
          todayKey: root.todayKey
          bornText: root.lifeBornText
          liveToText: root.lifeLiveToText
          onAction: function (name, arg) {
            root.handleAction(name, arg)
          }
        }
        Loader {
          id: worldViewLoader
          width: viewport.width
          visible: root.isSectionOpen("worldclock")
          Component.onCompleted: setSource(Qt.resolvedUrl("../araneadev.worldclock/WorldClockDropdown.qml"), {
            width: Qt.binding(function () {
              return worldViewLoader.width
            }),
            view: Qt.binding(function () {
              return root.worldClockPanel ? root.worldClockPanel.worldView : {}
            })
          })
        }
        Connections {
          target: root.worldDropdown
          function onRevealRequested(top, rowHeight) {
            viewport.reveal(top, rowHeight)
          }
          function onAction(name, arg) {
            if (root.worldClockPanel)
              root.worldClockPanel.handleAction(name, arg)
          }
        }
        Column {
          id: weatherPage
          width: viewport.width
          visible: root.isSectionOpen("weather")
          spacing: Style.space(12)
          Loader {
            id: weatherViewLoader
            width: viewport.width
            visible: root.isSectionOpen("weather")
            Component.onCompleted: setSource(Qt.resolvedUrl("../araneadev.weather/WeatherDropdown.qml"), {
              width: Qt.binding(function () {
                return weatherViewLoader.width
              }),
              view: Qt.binding(function () {
                return root.weatherPanel ? root.weatherPanel.weatherView : {}
              }),
              hourlyPoints: Qt.binding(function () {
                return root.weatherPanel ? root.weatherPanel.hourlyPoints : null
              }),
              editText: Qt.binding(function () {
                return root.weatherPanel ? root.weatherPanel.editText : ""
              })
            })
          }
          ClockWeatherPreferences {
            id: weatherPreferences
            objectName: "clockWeatherPreferences"
            width: parent.width
            visible: root.isSectionOpen("weather")
            unit: root.weatherPanel ? String(root.weatherPanel.setting("unit", "")) : ""
            refreshMinutes: root.weatherPanel ? root.weatherPanel.refreshMinutes : 15
            focusTarget: panel.focusTarget
            onSettingsRequested: function (values) {
              root.persistSection("weather", values)
            }
          }
        }
        Connections {
          target: root.weatherDropdown
          function onAction(name, arg) {
            if (root.weatherPanel)
              root.weatherPanel.handleAction(name, arg)
          }
        }
      }
    }
  }
}
