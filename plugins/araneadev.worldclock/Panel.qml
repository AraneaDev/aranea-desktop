// The World Clock owns its saved city list; the dropdown is a plain view.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "WorldCities.js" as Cities
import "WorldClockLogic.js" as Logic

Panel {
  id: root
  moduleName: "omarchy.elsewhen"
  ipcTarget: "omarchy.elsewhen"
  manageIpc: false

  // Clock owns the only native popup when this controller is embedded.
  property bool embedded: false
  // Owning Clock panel; page tokens are weather and worldclock.
  property var embeddingHost: null
  // Pure page view owned by the Clock popup.
  property var hostedDropdown: null
  // Clock's shared keyboard catcher, used after editor cancellation.
  property var hostedFocusTarget: null
  // Dynamic frame interface keeps Loader QObject metadata out of page bindings.
  readonly property var standaloneFrameItem: standaloneFrame.item
  // View targeted by keyboard and pointer operations in either mode.
  readonly property var activeDropdown: embedded ? hostedDropdown : standaloneFrameItem ? standaloneFrameItem.dropdownView : null
  // Focus remains with the owner of the currently visible section.
  readonly property var activeFocusTarget: embedded ? hostedFocusTarget : standaloneFrameItem ? standaloneFrameItem.focusTarget : null
  // Delayed work may only target this section while its owner is open.
  readonly property bool sectionActive: !embedded || (opened && embeddingHost && embeddingHost.opened && embeddingHost.activePage === "worldclock")

  // Reset the pointer state of whichever pure view is currently hosted.
  function disarmPointer() {
    if (root.activeDropdown && typeof root.activeDropdown.disarmPointer === "function")
      root.activeDropdown.disarmPointer()
  }
  // Host identity and entry id follow the bar slot, while IPC stays Elsewhen.
  property var anchorItem: null
  // The bar widget owning this panel and its inline entry.
  property var hostWidget: null
  // Coordinator identity is the owning slot rather than the nested panel.
  readonly property var barIdentity: hostWidget || root
  // Settings writes follow the plugin entry id injected by the host.
  readonly property string entryId: hostWidget && hostWidget.moduleName ? String(hostWidget.moduleName) : root.moduleName
  // Normalized saved city order, with exactly one home.
  property var cities: []
  // Selected saved-city row.
  property int selected: 0
  // Whether the inline city editor owns keyboard input.
  property bool adding: false
  // Current city search text.
  property string query: ""
  // Selected search-result index.
  property int matchIndex: 0
  // Bundled city records loaded once by FileView.
  property var catalog: []
  // Injectable boundaries also let embedded hosts supply cached zone data.
  property string systemZone: Quickshell.env("TZ") || ""
  // Optional injected timezone observations; null uses the system probe.
  property var probeData: null
  // Last sampled abbreviation and numeric offset by IANA zone.
  property var zoneData: probeData || ({})
  // Whether the one-time system zone discovery has succeeded.
  property bool systemProbed: false
  // Whether this open still needs to normalize the host settings.
  property bool awaitingLoad: false
  // Coalesces a search or minute sample arriving during a running probe.
  property bool probeAgain: false
  // Last real clock sample; retained while closed.
  property real sampleMs: Date.now()
  // Display-only screenshot time and cities, cleared on lifecycle changes.
  property var showcaseState: null
  // The displayed instant, from a showcase or the last clock sample.
  readonly property real nowMs: showcaseState ? showcaseState.nowMs : sampleMs
  // The city list presented without changing saved settings.
  readonly property var displayCities: showcaseState ? showcaseState.cities : cities
  // Ranked city search results from the bundled catalog.
  readonly property var matches: Cities.search(catalog, query, 5)
  // The one home row, with a harmless empty fallback before loading.
  readonly property var homeCity: displayCities.find(function (c) {
    return !!c.home
  }) || displayCities[0] || ({
      name: "",
      zone: "UTC"
    })
  // Subsolar point for the displayed instant.
  readonly property var sun: Logic.subsolarPoint(nowMs)
  // The selected city coordinates, or null when unavailable.
  readonly property var selectedPlace: {
    let c = adding ? matches[matchIndex] : displayCities[selected]
    let p = c ? Cities.resolvePlace(c, catalog) : null
    return p && typeof p.lat === "number" && typeof p.lon === "number" ? p : null
  }
  // Plain presentation state consumed by WorldClockDropdown.
  readonly property var worldView: ({
      homeName: homeCity.name,
      homeTime: timeFor(homeCity.zone),
      utcTime: Logic.localTime(0, nowMs),
      sunCaption: "overhead " + Logic.placeCaption(sun),
      sun: sun,
      rows: displayCities.map(function (c, i) {
        let p = Cities.resolvePlace(c, root.catalog)
        let place = typeof p.lat === "number" && typeof p.lon === "number" ? p : null
        let info = root.zoneData[c.zone]
        let offset = info ? info.offsetMinutes : 0
        return {
          name: c.name,
          abbrev: Logic.abbrevText(info, c.zone),
          time: root.timeFor(c.zone),
          offset: root.offsetFor(c.zone),
          node: Logic.nodeState(place, root.sun),
          stops: Logic.stripStops(place ? Logic.daylightWindow(place, offset, root.nowMs) : {
            kind: "night",
            rise: 0,
            set: 0
          }),
          now: Logic.nowFraction(offset, root.nowMs),
          home: !!c.home,
          selected: !root.adding && i === root.selected,
          place: place
        }
      }),
      adding: adding,
      query: query,
      matches: matches.map(function (c, i) {
        return {
          name: c.name,
          country: c.zone.split("/")[0],
          abbrev: Logic.abbrevText(root.zoneData[c.zone], c.zone),
          offset: root.offsetFor(c.zone),
          time: root.timeFor(c.zone),
          selected: i === root.matchIndex
        }
      }),
      selectedPlace: selectedPlace
    })
  // One plain city/time line for the bar tooltip using the last sample.
  readonly property string tooltipText: displayCities.map(function (c) {
    return c.name + " " + root.timeFor(c.zone)
  }).join("\n")

  // Formats wall-clock time from a zone observation; missing data stays unknown.
  function timeFor(zone) {
    let info = root.zoneData[zone]
    return zone === "UTC" ? Logic.localTime(0, root.nowMs) : info ? Logic.localTime(info.offsetMinutes, root.nowMs) : "-:-"
  }
  // Formats a zone offset relative to the displayed home city.
  function offsetFor(zone) {
    let info = root.zoneData[zone], home = root.zoneData[root.homeCity.zone]
    return info && home ? Logic.offsetText(info.offsetMinutes, home.offsetMinutes) : ""
  }
  // Refreshes host settings and zone observations before showing the panel.
  function open() {
    if (root.embedded) {
      if (!root.embeddingHost)
        return
      root.embeddingHost.openSection("worldclock")
      return
    }
    root.activateEmbedded()
  }
  // Start the selected page lifecycle without claiming a second native popup.
  function activateEmbedded() {
    if (root.embedded && (!root.embeddingHost || !root.embeddingHost.opened || root.embeddingHost.activePage !== "worldclock"))
      return
    root.showcaseState = null
    root.cancelAdd()
    if (!root.embedded && root.hostWidget && "settings" in root.hostWidget)
      root.settings = root.hostWidget.settings
    root.awaitingLoad = true
    root.sampleMs = Date.now()
    root.controller.show()
    root.requestProbe()
    Qt.callLater(function () {
      if (root.opened && !root.embedded)
        root.setCenterHoverRevealSuppressed(true)
    })
  }
  // Closes through the shared controller; lifecycle cleanup discards search.
  function close() {
    if (root.embedded) {
      if (!root.embeddingHost)
        return
      root.embeddingHost.close()
      return
    }
    root.setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }
  // Stop only this page and discard unsubmitted search state.
  function deactivateEmbedded() {
    root.controller.hide()
    root.disarmPointer()
  }
  // Toggles the shared popup lifecycle.
  function toggle() {
    if (root.embedded) {
      if (!root.embeddingHost)
        return
      if (root.opened)
        root.embeddingHost.close()
      else
        root.embeddingHost.openSection("worldclock")
      return
    }
    if (root.opened)
      root.close()
    else
      root.open()
  }
  // Cycles the bar coordinator from this widget identity.
  function switchPanel(direction) {
    // qmllint disable missing-property
    return root.bar && typeof root.bar.switchPanelFrom === "function" ? root.bar.switchPanelFrom(root.barIdentity, direction) : false
    // qmllint enable missing-property
  }
  // Keeps the center hover indicator from lingering behind a hotkey-opened panel.
  function setCenterHoverRevealSuppressed(value) {
    // qmllint disable missing-property
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value
    // qmllint enable missing-property
  }
  // Applies and persists a city edit only when its saved shape changes.
  function persistCities(next) {
    let saved = Cities.serialize(next)
    if (JSON.stringify(saved) === JSON.stringify(Cities.serialize(root.cities)))
      return
    root.cities = next
    root.writeCities(saved)
  }
  // Preserves other inline keys and writes through the owning bar entry.
  function writeCities(saved) {
    if (root.embedded) {
      if (root.embeddingHost)
        root.embeddingHost.persistSection("worldclock", {
          cities: saved
        })
      return
    }
    let entry = {
      id: root.entryId
    }
    for (let key in root.settings)
      if (key !== "id")
        entry[key] = root.settings[key]
    entry.cities = saved
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget)
      root.hostWidget.settings = entry
    // qmllint disable missing-property
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.entryId, entry)
    // qmllint enable missing-property
  }
  // Replaces only the untouched upstream seed and normalizes once per open.
  function loadCities() {
    if (!root.awaitingLoad || !root.opened)
      return
    root.awaitingLoad = false
    let raw = root.setting("cities", null)
    let offsets = {}
    for (let zone in root.zoneData)
      offsets[zone] = root.zoneData[zone].offsetMinutes
    let next = Cities.isElsewhenAutoSeed(raw, root.systemZone, offsets) ? Cities.serialize(Cities.SEED) : Cities.normalize(raw, root.systemZone)
    root.cities = next
    root.selected = Math.max(0, Math.min(root.selected, next.length - 1))
    if (JSON.stringify(Cities.serialize(next)) !== JSON.stringify(raw))
      root.writeCities(Cities.serialize(next))
  }
  // Samples the current relevant zones, discovering the system zone once.
  function requestProbe() {
    if (!root.opened || !root.sectionActive)
      return
    if (root.probeData !== null) {
      root.zoneData = root.probeData
      root.loadCities()
      return
    }
    if (zoneProbe.running) {
      root.probeAgain = true
      return
    }
    let zones = Cities.seedCandidateZones().concat(Cities.SEED.map(function (c) {
      return c.zone
    }))
    let raw = root.setting("cities", [])
    if (Array.isArray(raw))
      raw.forEach(function (c) {
        if (c && typeof c.zone === "string" && /^[A-Za-z_]+(\/[A-Za-z0-9_+\-]+)*$/.test(c.zone))
          zones.push(c.zone)
      })
    root.displayCities.concat(root.matches).forEach(function (c) {
      zones.push(c.zone)
    })
    if (root.systemZone)
      zones.push(root.systemZone)
    zones = zones.filter(function (z, i, list) {
      return list.indexOf(z) === i
    })
    zoneProbe.command = Logic.probeCommand(zones, !root.systemProbed && !root.systemZone, root.nowMs)
    zoneProbe.running = true
  }
  // Merges completed timezone observations and finishes initial normalization.
  function applyProbe(text) {
    if (!root.opened || !root.sectionActive)
      return
    let parsed = Logic.parseProbe(text), next = {}
    for (let old in root.zoneData)
      next[old] = root.zoneData[old]
    for (let zone in parsed.zones)
      next[zone] = parsed.zones[zone]
    root.zoneData = next
    if (parsed.local) {
      root.systemZone = parsed.local
      root.systemProbed = true
    }
    root.loadCities()
  }
  // Discards editor state and returns keyboard focus to the frame.
  function cancelAdd() {
    root.adding = false
    root.query = ""
    root.matchIndex = 0
    Qt.callLater(function () {
      if (root.opened && root.sectionActive && !root.adding && root.activeFocusTarget)
        root.activeFocusTarget.forceActiveFocus()
    })
  }
  // Routes view actions through the pure city list operations.
  function handleAction(name, arg) {
    if (!root.opened || !root.sectionActive || ((root.awaitingLoad || root.showcaseState) && name !== "select"))
      return
    if (name === "cancelAdd") {
      root.cancelAdd()
      return
    }
    if (name === "addStart") {
      root.adding = true
      root.query = ""
      root.matchIndex = 0
      Qt.callLater(function () {
        if (root.opened && root.sectionActive && root.adding && root.activeDropdown)
          root.activeDropdown.focusQuery()
      })
    } else if (name === "queryChanged") {
      root.query = String(arg)
      root.matchIndex = 0
      root.requestProbe()
    } else if (name === "matchSelect")
      root.matchIndex = Math.max(0, Math.min(root.matches.length - 1, Number(arg)))
    else if (name === "add") {
      let c = root.matches[Number(arg)]
      if (!c)
        return
      let added = Cities.add(root.cities, c)
      root.persistCities(added.cities)
      root.selected = added.index
      root.cancelAdd()
      root.requestProbe()
    } else if (!root.adding) {
      if (name === "select")
        root.selected = Math.max(0, Math.min(root.cities.length - 1, Number(arg)))
      else if (name === "remove") {
        root.persistCities(Cities.removeAt(root.cities, root.selected))
        root.selected = Math.min(root.selected, root.cities.length - 1)
      } else if (name === "moveUp" || name === "moveDown") {
        let moved = Cities.move(root.cities, root.selected, name === "moveUp" ? -1 : 1)
        root.persistCities(moved.cities)
        root.selected = moved.index
      } else if (name === "setHome")
        root.persistCities(Cities.setHome(root.cities, root.selected))
    }
  }
  // Forward the existing row navigation policy from either keyboard owner.
  function navigateKeyboard(dx, dy) {
    root.disarmPointer()
    // The stock catcher reserves h as Left; world clock uses it for home.
    if (dx < 0)
      root.handleAction("setHome", null)
    if (dy !== 0)
      root.handleAction("select", root.selected + dy)
  }
  // Saved rows do not have an Enter action; the search field owns its Enter.
  function activateKeyboard() {
    root.disarmPointer()
  }
  // Remove follows the same selected-row action as the standalone frame.
  function deleteKeyboard() {
    root.disarmPointer()
    root.handleAction("remove", null)
  }
  // Shared printable shortcuts keep city edits in the authoritative actions.
  function textKeyboard(text) {
    root.disarmPointer()
    if (text === "a" || text === "A")
      root.handleAction("addStart", null)
    else if (text === "[")
      root.handleAction("moveUp", null)
    else if (text === "]")
      root.handleAction("moveDown", null)
    else if (text === "h" || text === "H")
      root.handleAction("setHome", null)
  }
  // Display only; the normal open/close lifecycle clears every override.
  function showcase(payload) {
    if (!root.opened || !root.sectionActive)
      return "closed"
    try {
      let v = JSON.parse(payload)
      if (!v || typeof v.nowMs !== "number" || !isFinite(v.nowMs))
        return "invalid"
      root.showcaseState = {
        nowMs: v.nowMs,
        cities: Cities.normalize(v.cities || Cities.SEED, root.systemZone)
      }
      root.requestProbe()
      return "ok"
    } catch (error) {
      return "invalid"
    }
  }
  onOpenedChanged: if (!root.opened) {
    root.awaitingLoad = false
    root.probeAgain = false
    zoneProbe.running = false
    root.showcaseState = null
    root.cancelAdd()
    root.setCenterHoverRevealSuppressed(false)
  }
  FileView {
    id: catalogFile
    path: String(Qt.resolvedUrl("cities.json")).replace(/^file:\/\//, "")
    printErrors: false
    onLoaded: {
      try {
        root.catalog = Cities.parseCatalog(JSON.parse(catalogFile.text()))
      } catch (error) {
        root.catalog = []
      }
    }
  }
  Process {
    id: zoneProbe
    objectName: "worldZoneProbe"
    stdout: StdioCollector {
      id: probeOut
      waitForEnd: true
      onStreamFinished: root.applyProbe(probeOut.text)
    }
    onExited: if (root.probeAgain && root.opened) {
      root.probeAgain = false
      Qt.callLater(root.requestProbe)
    }
  }
  SystemClock {
    id: clock
    objectName: "worldMinuteClock"
    precision: SystemClock.Minutes
    enabled: root.opened
    onDateChanged: if (root.opened && !root.showcaseState) {
      root.sampleMs = clock.date.getTime()
      root.requestProbe()
    }
  }
  Loader {
    id: standaloneFrame
    active: !root.embedded
    sourceComponent: Component {
      Aranea.KeyboardPanelFrame {
        id: frame
        // Exposes the standalone view through the same interface as hosted views.
        property var dropdownView: dropdown
        objectName: "worldClockFrame"
        refined: true
        centerOnBar: true
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        blocked: root.adding
        contentWidth: frame.fittedContentWidth(Style.space(380))
        contentHeight: frame.fittedContentHeight(dropdown.implicitHeight)
        onCloseRequested: root.close()
        onTabRequested: function (direction) {
          root.switchPanel(direction)
        }
        onMoveRequested: function (dx, dy) {
          root.navigateKeyboard(dx, dy)
        }
        onActivateRequested: root.activateKeyboard()
        onDeleteRequested: root.deleteKeyboard()
        onTextKey: function (text) {
          root.textKeyboard(text)
        }
        Flickable {
          id: viewport
          objectName: "worldContent"
          anchors.fill: parent
          contentWidth: width
          contentHeight: dropdown.implicitHeight
          onHeightChanged: Qt.callLater(dropdown.revealCurrent)
          boundsBehavior: Flickable.StopAtBounds
          clip: true
          // Keyboard and editor focus remain visible when the saved list grows.
          function reveal(top, rowHeight) {
            if (top < contentY)
              contentY = Math.max(0, top)
            else if (top + rowHeight > contentY + height)
              contentY = Math.max(0, Math.min(contentHeight - height, top + rowHeight - height))
          }
          WorldClockDropdown {
            id: dropdown
            visible: root.opened
            width: viewport.width
            view: root.worldView
            onRevealRequested: function (top, rowHeight) {
              viewport.reveal(top, rowHeight)
            }
            onAction: function (name, arg) {
              root.handleAction(name, arg)
            }
          }
        }
      }
    }
  }
}
