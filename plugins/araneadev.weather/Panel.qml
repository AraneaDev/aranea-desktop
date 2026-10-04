// Aranea Weather (araneadev.weather, cloned from omarchy.weather): the
// weather dropdown. Stock's root logic stays (the wttr.in fetch, the
// open-meteo forecast and current fetch, the weather.json location file,
// the debounced geocoding suggestions, persistLocation through
// omarchy-weather-location, the units, the retry timers, the refresh
// timer, the IPC methods including edit, the hostWidget / barIdentity
// owner contract, centerOnBar and open / close / toggle). Changed here:
// open-meteo is asked for the extras (WeatherLogic.buildForecastUrl) plus
// one air-quality request per refresh, both at the configured coordinates
// or, in automatic mode, the ones wttr.in reports (WeatherLogic.wttrCoords).
// Added: the shared bundle, through which the per-monitor instances make
// one fetch per interval between them; handleAction for the view's keyed
// actions; the keyboard cursor; and the pending place while it saves. The
// pure view, WeatherDropdown, draws it in the shared keyboard frame; the
// rules are Model.js (stock) and WeatherLogic.js functions, tested under
// Node.
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model
import "WeatherLogic.js" as WeatherLogic
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared" as Aranea

// The weather widget's dropdown: the condition, temperature and place in
// the hero, rain soon, the details grid, the next 24 hours, air and UV,
// and the forecast days.
//
// BarWidget.qml owns the bar pill and hands this panel the button to anchor
// against.
Panel {
  id: root
  moduleName: "omarchy.weather"
  ipcTarget: "omarchy.weather"
  manageIpc: false

  // The bar button to anchor the popup against, set by BarWidget.qml.
  property var anchorItem: null
  // True while the popup was opened by hotkey (summon) rather than a click;
  // used to suppress the center hover reveal while it is up.
  property bool openedFromHotkey: false

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
  // ("araneadev.weather"), else this panel's own. moduleName itself stays
  // "omarchy.weather" for IPC. Weather writes no settings (the unit and
  // refreshMinutes are only read), so this only finds the other instances.
  readonly property string entryId: hostWidget && hostWidget.moduleName ? String(hostWidget.moduleName) : root.moduleName

  // Reveals the popup from a pointer click: no center-hover suppression,
  // since a click already carries its own hover state.
  function open() {
    openedFromHotkey = false
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
    locationFile.reload()
    root.autoRefresh()
  }

  // Reveals the popup from the IPC/hotkey path, suppressing the center
  // hover reveal while it is up (summoning moves no pointer).
  function openFromHotkey() {
    openedFromHotkey = true
    root.controller.show()
    locationFile.reload()
    root.autoRefresh()
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

  // Hides the popup and cancels any in-progress location edit.
  function close() {
    setCenterHoverRevealSuppressed(false)
    if (root.editingLocation)
      root.cancelEditingLocation()
    root.controller.hide()
  }

  // Opens the popup if closed, closes it if open.
  function toggle() {
    if (root.opened)
      root.close()
    else
      root.openFromHotkey()
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

  // Parsed wttr.in j1 response. Kept on failure so stale data stays visible.
  property var report: null
  // Parsed open-meteo daily-forecast response (current + 4-day daily).
  property var dailyForecastReport: null
  // The place name wttr.in reports for IP auto-detect (empty location).
  property string wttrLocation: ""

  // Configured location, read from the weather.json state file (owned by
  // omarchy-weather-location). The query is the wttr.in path segment
  // (coordinates when stored, else the encoded name); empty means IP
  // auto-detect. The watch makes hand edits take effect live.
  property var configuredLocationState: ({
      name: "",
      latitude: null,
      longitude: null
    })
  // The configured place name, "" for IP auto-detect.
  readonly property string configuredLocation: configuredLocationState.name
  // The wttr.in path segment for the configured location.
  readonly property string locationQuery: Model.wttrLocationQuery(configuredLocationState.name, configuredLocationState.latitude, configuredLocationState.longitude)

  // Keep the previous report visible while the new location loads. The
  // place label pulses while the new place saves, so stale data is never
  // presented under the newly configured location label for long.
  onLocationQueryChanged: {
    if (savingLocation)
      savingLocationQueryStarted = true
    forecastRetries = 0
    dailyForecastRetries = 0
    forecastProc.running = false
    dailyForecastProc.running = false
    airProc.running = false
    awaitingPeer = false
    // The stopped fetch no longer counts as one in flight.
    fetchClaimMs = 0
    // Neither the old place's automatic coordinates nor its extras carry
    // over: a name-only or automatic place waits for wttr's coordinates,
    // and the extras hide until the new place's answer lands.
    autoCoords = null
    forecast = null
    air = null
    Qt.callLater(root.autoRefresh)
  }

  // Watches weather.json so a hand edit (or omarchy-weather-location run
  // elsewhere) takes effect without reopening the popup.
  property FileView locationFile: FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/settings/weather.json"
    watchChanges: true
    printErrors: false
    onFileChanged: root.locationFile.reload()
    onLoaded: root.configuredLocationState = Model.parseLocationFile(root.locationFile.text())
    onLoadFailed: root.configuredLocationState = Model.parseLocationFile("")
  }

  // The first read can race shell startup (observed sporadically), leaving a
  // stored location unhonored until the next file write. One delayed reload
  // self-corrects; if the first read was fine it's a no-op, since identical
  // state doesn't change locationQuery and so triggers no refetch.
  Timer {
    interval: 1500
    running: true
    onTriggered: root.locationFile.reload()
  }

  // Consecutive failed wttr.in fetches since the last successful one.
  property int forecastRetries: 0
  // Consecutive failed open-meteo daily-forecast fetches since the last
  // successful one.
  property int dailyForecastRetries: 0

  // Click-to-edit state for the location label.
  property bool editingLocation: false
  // True while a committed location edit is being saved (omarchy-weather
  // -location is running): the new place shows at once and pulses.
  property bool savingLocation: false
  // True once the refetch that follows a save has actually started, so
  // finishSavingLocation knows the pending state's job is done.
  property bool savingLocationQueryStarted: false
  // Geocoding suggestions for the text currently in the location field.
  property var locationSuggestions: []
  // The highlighted row in locationSuggestions.
  property int suggestionIndex: 0
  // The latest location-field text queued for a geocode request.
  property string geocodePendingQuery: ""
  // The query the in-flight geocode request was started with.
  property string geocodeActiveQuery: ""
  // The location field's text as the view last reported it (its query
  // action); stock read the field itself.
  property string editQuery: ""
  // The text the field is seeded with when editing starts. Set only when
  // the field is deliberately reset, never echoed back from typing.
  property string editText: ""

  // Shared hero/bar icon state, updated with each successful weather response.
  property string label: ""

  // True once the configured location carries usable coordinates (picked
  // from geocoding suggestions, or hand-set with lat,lon).
  readonly property bool hasConfiguredCoordinates: !isNaN(parseFloat(String(configuredLocationState.latitude))) && !isNaN(parseFloat(String(configuredLocationState.longitude)))
  // wttr's current conditions when available; open-meteo's (bundled with the
  // much faster daily forecast fetch) fill the hero while wttr is in flight.
  readonly property var openMeteoCurrent: Model.openMeteoCurrentCondition(dailyForecastReport)
  // The current-conditions row in use: open-meteo first with configured
  // coordinates (it answers far faster), wttr otherwise, falling back to
  // open-meteo while wttr is still in flight.
  readonly property var current: (hasConfiguredCoordinates && openMeteoCurrent) ? openMeteoCurrent : ((report && report.current_condition && report.current_condition[0]) ? report.current_condition[0] : openMeteoCurrent)
  // wttr's resolved area for the current location (used for auto-detect's
  // place name and country).
  readonly property var areaInfo: report && report.nearest_area && report.nearest_area[0] ? report.nearest_area[0] : null
  // The resolved location's country, used to pick metric vs. imperial when
  // the unit setting does not say.
  readonly property string reportCountry: areaInfo && areaInfo.country && areaInfo.country[0] ? areaInfo.country[0].value : ""

  // Whether to show imperial units, from the unit setting, the locale and
  // the resolved location's country, in that order.
  readonly property bool useImperial: Model.shouldUseImperial(setting("unit", ""), Qt.locale().name, reportCountry)

  // Auto-refresh interval in minutes; clamped to a sane minimum.
  readonly property int refreshMinutes: Math.max(1, parseInt(setting("refreshMinutes", 15), 10) || 15)

  // The place name shown in the hero row: configured, else wttr's detected
  // area, else wttr's resolved area name.
  readonly property string reportLocation: configuredLocation || wttrLocation || (areaInfo && areaInfo.areaName && areaInfo.areaName[0] ? areaInfo.areaName[0].value : "")
  // The hero temperature's bare number, in the active unit.
  readonly property string reportTempNum: current ? String(useImperial ? current.temp_F : current.temp_C) : ""
  // The WIND stat, formatted with its unit.
  readonly property string reportWind: current ? (useImperial ? (current.windspeedMiles + " mph") : (current.windspeedKmph + " km/h")) : ""
  // The HUMID stat, formatted as a percent.
  readonly property string reportHumidity: current ? (current.humidity + "%") : ""

  // ---- The extras and the shared bundle.
  // The open-meteo response's extras (WeatherLogic.parseOpenMeteo: current,
  // hourly, minutely and the location's UTC offset), or null.
  property var forecast: null
  // The air-quality reading (WeatherLogic.parseAir), or null when the air
  // request failed: the chips hide.
  property var air: null
  // The coordinates wttr.in reported for the automatic location
  // (WeatherLogic.wttrCoords), which drive open-meteo while no
  // coordinates are configured; null until wttr answers.
  property var autoCoords: null
  // When the report on screen was fetched (Date.now(), by this instance or
  // the one it was adopted from): stamped only by the primary response
  // (open-meteo with configured coordinates, wttr j1 in automatic mode, as
  // Model.weatherResponseCompletesSave), so the air reading or the %l place
  // arriving alone never makes a failed refresh look fresh; 0 before any.
  property real fetchedAtMs: 0
  // When the bundle on screen was last published (any of its responses),
  // so the other instances take the later pieces too.
  property real publishedAtMs: 0
  // This instance's own last fetch, published for the other monitors'
  // instances: {locationQuery, fetchedAtMs, publishedAtMs, report, daily, forecast, air,
  // autoCoords, wttrLocation, label}; null before any.
  property var sharedWeather: null
  // True while an automatic refresh waits for another instance's fetch.
  property bool awaitingPeer: false
  // When this instance last started a fetch (Date.now()), so another
  // instance whose timer fires in the same moment sees it as fetching
  // before its processes report running.
  property real fetchClaimMs: 0
  // How many times an automatic refresh deferred for the bar to be injected.
  property int readyDefers: 0
  // Counts refreshes, so the open-meteo and air requests go out once per
  // refresh even when automatic mode asks twice (before and after wttr).
  property int refreshCycle: 0
  // The refresh and coordinates of the open-meteo request in flight.
  property string dailyForecastKey: ""
  // The refresh and coordinates open-meteo last answered for.
  property string forecastDoneKey: ""
  // The refresh and coordinates the last air request went out for.
  property string airKey: ""
  // True while any of this instance's weather requests is running.
  readonly property bool fetchInFlight: forecastProc.running || dailyForecastProc.running || airProc.running
  // A clock for the location-time readings (rain soon, the trend, the
  // trace): set on open, on new data and each minute while open.
  property real nowMs: Date.now()
  // "Now" in the forecast location's local time, as open-meteo's
  // timezone=auto times read (WeatherLogic.nowIsoAt).
  readonly property string nowIso: WeatherLogic.nowIsoAt(root.nowMs, root.forecast ? root.forecast.utcOffsetSeconds : 0)
  // Today at the forecast location ("yyyy-MM-dd"), the host's own day
  // before open-meteo has answered.
  readonly property string todayIso: root.forecast ? root.nowIso.slice(0, 10) : Qt.formatDate(new Date(root.nowMs), "yyyy-MM-dd")
  // The next-24h trace (WeatherLogic.hourlyPoints), or null.
  readonly property var hourlyPoints: root.forecast ? WeatherLogic.hourlyPoints(root.forecast.hourly, root.nowIso, 24) : null

  // ---- The keyboard cursor (place and refresh).
  // Whether keyboard or pointer navigation has placed a cursor yet.
  property bool cursorActive: false
  // True while the keyboard drives the cursor; any pointer action clears
  // it. The view outlines the cursor only then.
  property bool keyboardCursor: false
  // The control the cursor is on: "place", "refresh" or "clear".
  property string cursorSection: "place"
  // The control the cursor was deliberately put on (a move or a keyboard
  // reveal; never an open or a hover); Enter refuses while it is "" or not
  // the cursor's (CursorLogic.cursorConfirmed).
  property string cursorKey: ""
  // The controls the keyboard walks, in order: the place label (while a
  // place shows) and the updated label (once fetched).
  readonly property var cursorSections: {
    var list = []
    if (root.reportLocation !== "")
      list.push("place")
    if (root.fetchedAtMs > 0)
      list.push("refresh")
    return list
  }

  // The forecast days the view shows (today first, up to 4), each keyed
  // by its date.
  readonly property var dayRows: WeatherLogic.forecastFromToday(root.report, root.dailyForecastReport, root.todayIso, 4).map(function (day, i) {
    var date = String(day.date || "").slice(0, 10)
    return {
      key: date,
      label: i === 0 && date === root.todayIso ? "Today" : root.shortDayName(date),
      glyph: Model.dayIcon(day),
      hi: Model.bareTempForDay(day, "max", root.useImperial),
      lo: Model.bareTempForDay(day, "min", root.useImperial)
    }
  })

  // The plain view object WeatherDropdown draws (see its view property).
  readonly property var weatherView: {
    var fc = root.forecast && root.forecast.current ? root.forecast.current : ({})
    var temp = root.reportTempNum !== "" && root.reportTempNum !== "undefined" ? root.reportTempNum + "°" : ""
    var feels = root.current ? String(root.useImperial ? root.current.FeelsLikeF : root.current.FeelsLikeC) : ""
    var editing = root.editingLocation && !root.savingLocation
    return {
      hero: {
        glyph: root.label,
        temp: temp,
        // From the same source as the glyph (open-meteo's code when it has
        // answered, as Model.currentIcon), so the two never disagree.
        label: root.current ? WeatherLogic.conditionLabel(root.openMeteoCurrent || root.current) : "Fetching forecast…",
        place: root.reportLocation,
        updated: root.fetchedAtMs > 0 ? "updated " + Qt.formatTime(new Date(root.fetchedAtMs), "HH:mm") : "",
        loading: root.fetchInFlight || root.awaitingPeer
      },
      rainSoon: root.forecast ? WeatherLogic.rainSoon(root.forecast.minutely, root.nowIso) : "",
      details: root.current ? WeatherLogic.detailCells({
        feels: feels !== "" && feels !== "undefined" ? feels + "°" : "",
        humid: root.current.humidity !== undefined ? root.reportHumidity : "",
        wind: root.reportWind,
        windDeg: fc.wind_direction_10m,
        gustsKmh: fc.wind_gusts_10m,
        pressureHpa: fc.surface_pressure,
        trend: root.forecast ? WeatherLogic.pressureTrend(root.forecast.hourly, root.nowIso) : "",
        visibilityM: fc.visibility,
        imperial: root.useImperial
      }) : [],
      hourly: {
        visible: !!root.hourlyPoints && root.hourlyPoints.temp.length > 0,
        caption: WeatherLogic.hourlyCaption(root.hourlyPoints, root.useImperial),
        labels: root.forecast ? WeatherLogic.hourLabels(root.forecast.hourly, root.nowIso, 24, 5) : []
      },
      air: WeatherLogic.airView(root.air),
      days: root.dayRows,
      edit: {
        active: editing,
        suggestions: WeatherLogic.suggestionRows(root.locationSuggestions),
        saving: root.savingLocation,
        cursor: root.suggestionIndex
      },
      cursor: {
        active: root.cursorActive && root.keyboardCursor,
        section: root.cursorSection,
        index: 0
      },
      keyHint: editing ? "↑↓ pick · enter save · esc cancel" : "enter select · e edit place · r refresh"
    }
  }

  // Re-fetches the forecast now (an explicit refresh: the updated label,
  // `r`, the pill's middle click; automatic ones go through autoRefresh):
  // wttr.in always, open-meteo's forecast and the air reading right away
  // when coordinates are configured (otherwise once wttr reports the
  // auto-detected area), and the auto-detect place name when unset.
  function refresh() {
    awaitingPeer = false
    peerWaitTimer.stop()
    root.fetchClaimMs = Date.now()
    root.refreshCycle++
    // Each full refresh cycle gets a fresh retry budget, so an earlier
    // exhausted round (e.g. waking with the network still down) doesn't
    // starve retries for the rest of the session.
    forecastRetries = 0
    dailyForecastRetries = 0
    if (!forecastProc.running)
      forecastProc.running = true
    if (root.locationQuery === "" && !locationProc.running)
      locationProc.running = true
    // With stored coordinates this fetches open-meteo right away - no need
    // to wait for the slow wttr response. Without them it uses the last
    // coordinates wttr reported, if any.
    refreshDailyForecast(null)
  }

  // An automatic refresh (the timer, an open, a location change): adopts a
  // fresh report another instance (or this one) already fetched, waits
  // while another instance is fetching, else fetches
  // (WeatherLogic.refreshPlan). A bundle counts as fresh for a minute less
  // than the refresh interval, so a timer firing on schedule still finds
  // its own last report stale.
  function autoRefresh() {
    var hosts = root.instancePanels()
    var bundles = []
    var peerFetching = false
    for (var i = 0; i < hosts.length; i++) {
      var p = hosts[i]
      bundles.push(p.sharedWeather)
      if (p !== root && p.locationQuery === root.locationQuery && typeof p.isFetching === "function" && p.isFetching())
        peerFetching = true
    }
    var freshMinutes = Math.max(root.refreshMinutes / 2, root.refreshMinutes - 1)
    var fresh = WeatherLogic.sharedBundle(bundles, root.locationQuery, Date.now(), freshMinutes)
    var plan = WeatherLogic.refreshPlan({
      ready: !!root.bar || root.readyDefers >= 6,
      selfFetching: root.isFetching(),
      fresh: !!fresh,
      peerFetching: peerFetching
    })
    if (plan === "defer") {
      root.readyDefers++
      readyTimer.restart()
    } else if (plan === "adopt") {
      root.adoptShared(fresh)
    } else if (plan === "wait") {
      root.awaitingPeer = true
      peerWaitTimer.restart()
    } else if (plan === "fetch") {
      root.refresh()
    }
  }

  // Whether this instance is fetching, or has just claimed a fetch whose
  // processes have not reported running yet.
  function isFetching() {
    return root.fetchInFlight || Date.now() - root.fetchClaimMs < 2000
  }

  // Every instance's loaded panel, this one included, through the bar's
  // moduleWidgets(entryId) (each bar surface hosts its own); just this one
  // before the bar is injected.
  function instancePanels() {
    // qmllint disable missing-property
    var hosts = root.bar && typeof root.bar.moduleWidgets === "function" ? root.bar.moduleWidgets(root.entryId) : []
    // qmllint enable missing-property
    var panels = []
    for (var i = 0; i < hosts.length; i++) {
      var p = hosts[i] ? hosts[i].weatherPanel : null
      if (p && panels.indexOf(p) < 0)
        panels.push(p)
    }
    if (panels.indexOf(root) < 0)
      panels.push(root)
    return panels
  }

  // Publishes this instance's report after one of its own responses landed,
  // and hands it to the other instances (offerShared). PRIMARY (the
  // response that makes a refresh, see fetchedAtMs) also stamps the
  // fetch time.
  function publishShared(primary) {
    root.publishedAtMs = Date.now()
    if (primary === true)
      root.fetchedAtMs = root.publishedAtMs
    root.nowMs = root.publishedAtMs
    root.sharedWeather = {
      locationQuery: root.locationQuery,
      fetchedAtMs: root.fetchedAtMs,
      publishedAtMs: root.publishedAtMs,
      report: root.report,
      daily: root.dailyForecastReport,
      forecast: root.forecast,
      air: root.air,
      autoCoords: root.autoCoords,
      wttrLocation: root.wttrLocation,
      label: root.label
    }
    var hosts = root.instancePanels()
    for (var i = 0; i < hosts.length; i++)
      if (hosts[i] !== root && typeof hosts[i].offerShared === "function")
        hosts[i].offerShared(root.sharedWeather)
  }

  // Takes another instance's freshly published BUNDLE when it is for this
  // instance's location and newer than what this one shows.
  function offerShared(bundle) {
    if (bundle && bundle.locationQuery === root.locationQuery && bundle.publishedAtMs > root.publishedAtMs)
      root.adoptShared(bundle)
  }

  // Shows BUNDLE's report instead of fetching: the wttr and open-meteo
  // responses, the extras, the air reading and the bar icon. An older or
  // equal bundle changes nothing; either way the wait is over.
  function adoptShared(bundle) {
    root.awaitingPeer = false
    peerWaitTimer.stop()
    if (!bundle || !(bundle.publishedAtMs > root.publishedAtMs))
      return
    root.report = bundle.report || root.report
    root.dailyForecastReport = bundle.daily || root.dailyForecastReport
    root.forecast = bundle.forecast || root.forecast
    root.air = bundle.air || null
    root.autoCoords = bundle.autoCoords || root.autoCoords
    if (bundle.wttrLocation)
      root.wttrLocation = bundle.wttrLocation
    root.label = bundle.label || root.label
    root.fetchedAtMs = bundle.fetchedAtMs
    root.publishedAtMs = bundle.publishedAtMs
    root.nowMs = Date.now()
    root.finishSavingLocation()
  }

  // Fetches open-meteo's forecast (with the extras) and the air reading for
  // the configured coordinates, or for sourceCoords (wttr's, just reported)
  // or the last-known automatic coordinates when unconfigured. Once per
  // refresh and coordinates: automatic mode asks before and after wttr.
  function refreshDailyForecast(sourceCoords) {
    if (dailyForecastProc.running)
      return
    var lat = parseFloat(String(root.configuredLocationState.latitude))
    var lon = parseFloat(String(root.configuredLocationState.longitude))
    if (isNaN(lat) || isNaN(lon)) {
      var coords = sourceCoords || root.autoCoords
      if (!coords)
        return
      lat = coords.lat
      lon = coords.lon
    }
    if (isNaN(lat) || isNaN(lon))
      return
    var key = root.refreshCycle + "|" + lat + "," + lon
    if (key === root.forecastDoneKey)
      return
    root.dailyForecastKey = key
    dailyForecastProc.command = ["curl", "-fsS", "--max-time", "5", WeatherLogic.buildForecastUrl(lat, lon)]
    dailyForecastProc.running = true
    if (key !== root.airKey && !airProc.running) {
      root.airKey = key
      airProc.command = ["curl", "-fsS", "--max-time", "5", WeatherLogic.buildAirUrl(lat, lon)]
      airProc.running = true
    }
  }

  // ---- Location editing. Clicking the location label swaps it for a search
  //      field; picking a geocoded suggestion persists name + coordinates
  //      through omarchy-weather-location. An empty commit returns to auto.
  function startEditingLocation() {
    if (savingLocation)
      return
    editingLocation = true
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    suggestionIndex = 0
    // Seeding the field: stock's text change looked the current place up
    // too, so the suggestions show it.
    editText = root.configuredLocation
    editQuery = root.configuredLocation
    geocodeDebounce.restart()
  }

  // Closes the location editor without committing, and returns focus to the
  // popup's key catcher.
  function cancelEditingLocation() {
    editingLocation = false
    savingLocation = false
    savingLocationQueryStarted = false
    locationSuggestions = []
    geocodeDebounce.stop()
    root.focusPanel()
  }

  // Hands keyboard focus back to the frame's key catcher.
  function focusPanel() {
    Qt.callLater(function () {
      if (panel.focusTarget)
        panel.focusTarget.forceActiveFocus()
    })
  }

  // Commits the field's TEXT with PICK, the highlighted suggestion's
  // {index, key} (null for the raw text): an empty commit clears back to
  // auto-detect, otherwise the place is persisted. A pick whose row no
  // longer carries its key is refused.
  function commitLocation(text, pick) {
    var suggestions = []
    var index = 0
    if (pick) {
      if (!WeatherLogic.suggestionAt(root.locationSuggestions, pick.index, pick.key))
        return
      suggestions = root.locationSuggestions
      index = pick.index
    }
    var location = Model.locationCommit(text, suggestions, index)
    if (location.name === "") {
      clearLocation()
      return
    }
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: location.name,
      latitude: location.latitude,
      longitude: location.longitude
    }
    root.focusPanel()
    persistLocation(location.name, location.latitude, location.longitude)
  }

  // Clears the configured location, returning to IP auto-detect. Shown at
  // once, pulsing until omarchy-weather-location exits.
  function clearLocation() {
    persistLocation("", null, null)
    wttrLocation = ""
    cancelEditingLocation()
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = Model.parseLocationFile("")
  }

  // Commits a geocoding suggestion picked by click.
  function pickSuggestion(suggestion) {
    if (!suggestion)
      return
    savingLocation = true
    savingLocationQueryStarted = false
    configuredLocationState = {
      name: suggestion.name,
      latitude: suggestion.latitude,
      longitude: suggestion.longitude
    }
    root.focusPanel()
    persistLocation(suggestion.name, suggestion.latitude, suggestion.longitude)
  }

  // Closes the editor once the post-save refetch has actually started, but
  // never while omarchy-weather-location still runs: then locationSaved,
  // on its exit, is what ends the pending place (WeatherLogic.saveEnds).
  function finishSavingLocation() {
    if (WeatherLogic.saveEnds(savingLocation, savingLocationQueryStarted, locationSaveProc.running))
      cancelEditingLocation()
  }

  // Writes the location to weather.json via omarchy-weather-location: a
  // name with coordinates, a name alone, or a clear back to auto-detect.
  function persistLocation(name, latitude, longitude) {
    if (name && latitude !== null && longitude !== null)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name, latitude + "," + longitude]
    else if (name)
      locationSaveProc.command = ["omarchy-weather-location", "--set", name]
    else
      locationSaveProc.command = ["omarchy-weather-location", "--clear"]
    locationSaveProc.running = true
  }

  // omarchy-weather-location exited: re-read the file (a failed save puts
  // the real place back), refresh when saving the place already in use left
  // nothing to refetch, and end the pending state.
  function locationSaved() {
    locationFile.reload()
    if (!root.savingLocation)
      return
    if (!root.savingLocationQueryStarted) {
      root.savingLocationQueryStarted = true
      root.forecastRetries = 0
      root.dailyForecastRetries = 0
      forecastProc.running = false
      dailyForecastProc.running = false
      root.fetchClaimMs = 0
      Qt.callLater(root.autoRefresh)
    }
    root.cancelEditingLocation()
  }

  // Debounced geocoding. Only one curl runs at a time; if the query moved on
  // while a fetch was in flight, the latest query is fetched right after.
  function requestGeocode() {
    var query = root.editQuery.trim()
    if (query.length < 2) {
      locationSuggestions = []
      return
    }
    geocodePendingQuery = query
    if (!geocodeProc.running)
      startGeocode()
  }

  // Starts the geocoding curl for geocodePendingQuery.
  function startGeocode() {
    geocodeActiveQuery = geocodePendingQuery
    geocodeProc.command = ["curl", "-fsS", "--max-time", "5", "https://geocoding-api.open-meteo.com/v1/search?name=" + encodeURIComponent(geocodeActiveQuery) + "&count=5&language=en&format=json"]
    geocodeProc.running = true
  }

  // Moves the highlighted suggestion by DELTA, within the list (stock's Up
  // and Down in the field).
  function stepSuggestion(delta) {
    if (!root.editingLocation || root.savingLocation)
      return
    if (delta < 0 && root.suggestionIndex > 0)
      root.suggestionIndex--
    else if (delta > 0 && root.suggestionIndex < root.locationSuggestions.length - 1)
      root.suggestionIndex++
  }

  // ---- The view's actions and the keyboard cursor.
  // Carries out one WeatherDropdown action (see its action signal). Pointer
  // actions hand the cursor back from the keyboard; a keyed pick whose row
  // changed under it is refused; the rest map onto stock's location
  // functions.
  function handleAction(name, arg) {
    var a = arg || ({})
    if (name === "query") {
      root.editQuery = String(a.text || "")
      if (root.editingLocation && !root.savingLocation)
        geocodeDebounce.restart()
    } else if (name === "commit") {
      if (root.editingLocation && !root.savingLocation)
        root.commitLocation(String(a.text || ""), a.pick || null)
    } else if (name === "cancel") {
      root.cancelEditingLocation()
    } else if (name === "step") {
      root.stepSuggestion(Number(a.delta) || 0)
    } else if (name === "hover") {
      // Only the control's own fill: a hover never moves the cursor or the
      // highlighted suggestion, nor hides the outline.
    } else {
      root.keyboardCursor = false
      if (name === "editPlace") {
        root.startEditingLocation()
      } else if (name === "pick") {
        if (root.editingLocation && !root.savingLocation)
          root.pickSuggestion(WeatherLogic.suggestionAt(root.locationSuggestions, a.index, a.key))
      } else if (name === "clearPlace") {
        if (!root.savingLocation)
          root.clearLocation()
      } else if (name === "refresh") {
        root.refresh()
      }
    }
  }

  // Keeps the cursor on a control the keyboard can reach.
  function clampCursor() {
    var sections = root.cursorSections
    if (sections.length > 0 && sections.indexOf(root.cursorSection) < 0) {
      root.cursorSection = sections[0]
      root.cursorKey = ""
    }
  }

  // Moves the keyboard cursor by DELTA through the controls; where it
  // lands is a deliberate choice.
  function moveCursor(delta) {
    var sections = root.cursorSections
    if (sections.length === 0)
      return
    var at = Math.max(0, sections.indexOf(root.cursorSection))
    var next = Math.max(0, Math.min(sections.length - 1, at + delta))
    root.cursorSection = sections[next]
    root.cursorKey = root.cursorSection
  }

  // Shows the keyboard cursor where it is, on the control it sits on: the
  // outline marks Enter's target, so the revealed control is the one Enter
  // then acts on.
  function revealCursor() {
    root.clampCursor()
    root.cursorActive = true
    root.keyboardCursor = true
    root.cursorKey = root.cursorSection
  }

  // Enter or Space in the frame (never in the place field, which takes its
  // own keys): like any first key, it only reveals a hidden cursor; else
  // the chosen control acts (CursorLogic.pressIntent, cursorConfirmed).
  function activateCursor() {
    if (CursorLogic.pressIntent(root.cursorActive, root.keyboardCursor) !== "act") {
      root.revealCursor()
      return
    }
    if (!CursorLogic.cursorConfirmed([
      {
        key: root.cursorSection
      }
    ], root.cursorKey, 0))
      return
    if (root.cursorSection === "place")
      root.startEditingLocation()
    else if (root.cursorSection === "refresh")
      root.refresh()
  }

  // The short English day name for an ISO date ("Sat").
  function shortDayName(dateString) {
    return Model.dayName(dateString, function (date) {
      return Qt.locale("en_US").dayName(date.getDay(), Locale.ShortFormat)
    })
  }

  // A fresh open shows no cursor until the first navigation key, and
  // reads the location-time readings for now.
  onOpenedChanged: {
    root.keyboardCursor = false
    root.cursorActive = false
    root.cursorKey = ""
    if (root.opened)
      root.nowMs = Date.now()
  }
  onCursorSectionsChanged: root.clampCursor()

  Process {
    id: forecastProc
    command: ["curl", "-fsS", "--max-time", "10", "https://wttr.in/" + root.locationQuery + "?format=j1"]
    stdout: StdioCollector {
      id: forecastOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(forecastOut.text || "").trim()
        if (!raw) {
          root.scheduleForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          root.report = parsed
          if (!root.hasConfiguredCoordinates)
            root.label = Model.provisionalCurrentIcon(parsed.current_condition && parsed.current_condition[0], root.label)
          root.forecastRetries = 0
          var coords = WeatherLogic.wttrCoords(raw)
          if (coords)
            root.autoCoords = coords
          root.publishShared(Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "wttr"))
            root.finishSavingLocation()
          // Stored coordinates already drove the fast open-meteo fetch from
          // refresh(); only auto-detect needs the area wttr reported.
          if (isNaN(parseFloat(String(root.configuredLocationState.latitude))))
            root.refreshDailyForecast(coords)
        } catch (e) {
          // Keep last-good report visible, but try again shortly.
          root.scheduleForecastRetry()
        }
      }
    }
  }

  // wttr.in can be slow or flaky, especially for a location it hasn't
  // cached yet. Retry a few times before leaving it to the refresh timer.
  function scheduleForecastRetry() {
    if (forecastRetries >= 3)
      return
    forecastRetries++
    forecastRetryTimer.restart()
  }

  Timer {
    id: forecastRetryTimer
    interval: 2500
    onTriggered: if (!forecastProc.running)
      forecastProc.running = true
  }

  // With configured coordinates this fetch is the only thing that updates the
  // bar icon, so a dropped response (e.g. waking before the network is back)
  // must retry rather than wait out the refresh timer with a stale icon.
  function scheduleDailyForecastRetry() {
    if (dailyForecastRetries >= 3)
      return
    dailyForecastRetries++
    dailyForecastRetryTimer.restart()
  }

  Timer {
    id: dailyForecastRetryTimer
    interval: 2500
    onTriggered: root.refreshDailyForecast(null)
  }

  Process {
    id: dailyForecastProc
    stdout: StdioCollector {
      id: dailyForecastOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(dailyForecastOut.text || "").trim()
        if (!raw) {
          root.scheduleDailyForecastRetry()
          return
        }
        try {
          var parsed = JSON.parse(raw)
          var parsedCurrent = Model.openMeteoCurrentCondition(parsed)
          root.dailyForecastReport = parsed
          root.forecast = WeatherLogic.parseOpenMeteo(raw)
          root.label = Model.currentIcon(parsedCurrent, root.label)
          root.dailyForecastRetries = 0
          root.forecastDoneKey = root.dailyForecastKey
          root.publishShared(Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
          if (Model.weatherResponseCompletesSave(root.hasConfiguredCoordinates, "open-meteo"))
            root.finishSavingLocation()
        } catch (e) {
          // Keep last-good daily forecast visible, but try again shortly.
          root.scheduleDailyForecastRetry()
        }
      }
    }
  }

  // One air-quality request per refresh, at open-meteo's coordinates. A
  // failure hides the chips (no retry; the next refresh asks again).
  Process {
    id: airProc
    stdout: StdioCollector {
      id: airOut
      waitForEnd: true
      onStreamFinished: {
        root.air = WeatherLogic.parseAir(String(airOut.text || ""))
        // Published either way, so the other instances drop a stale
        // reading when this request failed.
        root.publishShared(false)
      }
    }
  }

  Process {
    id: geocodeProc
    stdout: StdioCollector {
      id: geocodeOut
      waitForEnd: true
      onStreamFinished: {
        root.locationSuggestions = root.editingLocation ? Model.parseGeocodingResults(geocodeOut.text) : []
        root.suggestionIndex = 0
        if (root.geocodePendingQuery !== root.geocodeActiveQuery)
          Qt.callLater(root.startGeocode)
      }
    }
  }

  Timer {
    id: geocodeDebounce
    interval: 300
    onTriggered: root.requestGeocode()
  }

  // omarchy-weather-location; locationSaved runs once it has exited.
  Process {
    id: locationSaveProc
    onRunningChanged: if (!locationSaveProc.running)
      root.locationSaved()
  }

  Process {
    id: locationProc
    command: ["curl", "-fsS", "--max-time", "4", "https://wttr.in/?format=%l"]
    stdout: StdioCollector {
      id: locationOut
      waitForEnd: true
      onStreamFinished: {
        var raw = String(locationOut.text || "").trim()
        if (!raw)
          return
        root.wttrLocation = raw.split(",")[0]
        root.publishShared(false)
      }
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.autoRefresh()
  }

  // Asks autoRefresh again while the bar is not injected yet (a start-up
  // refresh fires before the host hands the bar over), so every instance
  // can see the others before one of them fetches.
  Timer {
    id: readyTimer
    interval: 500
    onTriggered: root.autoRefresh()
  }

  // Gives up waiting for another instance's fetch (it failed, or its
  // monitor went away) and asks autoRefresh again.
  Timer {
    id: peerWaitTimer
    interval: 15000
    onTriggered: {
      root.awaitingPeer = false
      root.autoRefresh()
    }
  }

  // Moves the location-time readings along once a minute while open.
  Timer {
    interval: 60000
    repeat: true
    running: root.opened
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget

    function open(): void {
      root.openFromHotkey()
    }
    function close(): void {
      root.close()
    }
    function show(): void {
      root.openFromHotkey()
    }
    function hide(): void {
      root.close()
    }
    function toggle(): void {
      root.toggle()
    }
    function edit(): void {
      root.openFromHotkey()
      root.startEditingLocation()
    }
  }

  Aranea.KeyboardPanelFrame {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    // The place field takes its own keys (Up and Down come back as the
    // view's step action); while a place saves the field is gone and the
    // frame has the keys again.
    blocked: root.editingLocation && !root.savingLocation
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(dropdown.implicitHeight)
    onCloseRequested: root.close()
    onTabRequested: function (direction) {
      dropdown.disarmPointer()
      root.keyboardCursor = true
      root.switchPanel(direction)
    }
    onMoveRequested: function (dx, dy) {
      dropdown.disarmPointer()
      // The first key after opening or after pointer use only reveals the
      // cursor where it is.
      if (!root.cursorActive || !root.keyboardCursor) {
        root.revealCursor()
        return
      }
      root.clampCursor()
      root.moveCursor(dy !== 0 ? dy : dx)
    }
    onActivateRequested: {
      dropdown.disarmPointer()
      root.activateCursor()
    }
    onTextKey: function (t) {
      dropdown.disarmPointer()
      if (root.editingLocation)
        return
      if (t === "r" || t === "R")
        root.refresh()
      else if (t === "e" || t === "E")
        root.startEditingLocation()
    }

    Item {
      anchors.fill: parent
      clip: true

      WeatherDropdown {
        id: dropdown
        width: parent.width
        view: root.weatherView
        hourlyPoints: root.hourlyPoints
        editText: root.editText
        onAction: function (name, arg) {
          root.handleAction(name, arg)
        }
      }
    }
  }
}
