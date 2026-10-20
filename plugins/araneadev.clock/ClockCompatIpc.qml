// Legacy page targets belong to the mounted clock only without standalone entries.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

Item {
  id: compat
  // Mounted clock widget, retaining the shell's own-entry peer permission.
  required property var host
  // Public, read-only bar layout used solely to preserve standalone precedence.
  readonly property var layout: host.bar ? host.bar.layoutConfig : ({})
  // Whether Weather's native target belongs to this consolidated clock.
  readonly property bool weatherEnabled: !hasStandalone(["omarchy.weather", "araneadev.weather"])
  // Whether Elsewhen's target belongs to this consolidated clock.
  readonly property bool worldClockEnabled: !hasStandalone(["omarchy.elsewhen", "araneadev.worldclock"])

  // Accept both string and object entries in every public layout section.
  function hasStandalone(ids) {
    let sections = layout || {}
    for (let key in sections) {
      let entries = sections[key]
      if (!Array.isArray(entries))
        continue
      for (let i = 0; i < entries.length; i++) {
        let id = typeof entries[i] === "string" ? entries[i] : entries[i] ? entries[i].id : ""
        if (ids.indexOf(id) >= 0)
          return true
      }
    }
    return false
  }

  // Hiding a legacy target must leave another selected page alone.
  function closeSection(page) {
    if (host.isSectionOpen(page))
      host.close()
  }

  // Select Weather before the editor's guarded deferred focus runs.
  function editWeather() {
    host.openSection("weather")
    if (host.weatherPanel)
      host.weatherPanel.startEditingLocation()
  }

  // A showcase is display-only and finds an already open own-clock peer.
  function showcaseWorld(payload) {
    let peers = host.bar && typeof host.bar.moduleWidgets === "function" ? host.bar.moduleWidgets(host.moduleName) : [host]
    for (let i = 0; i < peers.length; i++) {
      let peer = peers[i]
      if (peer && peer.isSectionOpen("worldclock") && peer.worldClockPanel)
        return peer.worldClockPanel.showcase(payload)
    }
    return "closed"
  }

  Loader {
    active: compat.weatherEnabled
    sourceComponent: Component {
      IpcHandler {
        target: "omarchy.weather"
        function open(): void {
          compat.host.openSection("weather")
        }
        function show(): void {
          compat.host.openSection("weather")
        }
        function close(): void {
          compat.closeSection("weather")
        }
        function hide(): void {
          compat.closeSection("weather")
        }
        function toggle(): void {
          compat.host.toggleSection("weather")
        }
        function edit(): void {
          compat.editWeather()
        }
      }
    }
  }
  Loader {
    active: compat.worldClockEnabled
    sourceComponent: Component {
      IpcHandler {
        target: "omarchy.elsewhen"
        function open(): void {
          compat.host.openSection("worldclock")
        }
        function show(): void {
          compat.host.openSection("worldclock")
        }
        function close(): void {
          compat.closeSection("worldclock")
        }
        function hide(): void {
          compat.closeSection("worldclock")
        }
        function toggle(): void {
          compat.host.toggleSection("worldclock")
        }
        function showcase(payload: string): string {
          return compat.showcaseWorld(payload)
        }
      }
    }
  }
}
