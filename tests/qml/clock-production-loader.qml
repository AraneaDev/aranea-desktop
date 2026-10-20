//@ pragma OmarchyLoadPatch
// Installed plugins are dynamic Registry entry points outside the shell tree.
// Importing optional plugin directories here would hide their qs: loader bug.
import QtQuick
import Quickshell
import "lib"
import "services" as Services

ShellRoot {
  id: fixture
  QmlTest {
    id: t
  }
  Services.PluginRegistry {
    id: registry
  }
  QtObject {
    id: bar
    property string position: "top"
    property bool vertical: false
    property int barSize: 26
    property color foreground: "white"
    property color barForeground: "white"
    property color urgent: "red"
    property color background: "#17151f"
    property string fontFamily: "monospace"
    property bool foregroundAnimationEnabled: false
    property var activePopout: null
    property var layoutConfig: ({
        center: ["araneadev.clock"]
      })
    function requestPopout(owner) {
      activePopout = owner
    }
    function releasePopout(owner) {
      if (activePopout === owner)
        activePopout = null
    }
    function hideTooltip(owner) {
    }
    function showTooltip(owner, text) {
    }
    function setCenterHoverRevealSuppressed(value) {
    }
    function moduleWidgets(id) {
      return []
    }
  }
  FloatingWindow {
    visible: true
    implicitWidth: 1000
    implicitHeight: 800
    Loader {
      id: installed
    }
    Loader {
      id: calendarOnly
    }
  }
  // Resolve an external plugin entry point through the production Registry.
  function loadClock(loader, directory) {
    var entry = registry.entryPointUrl({
      entryPoints: {
        barWidget: "BarWidget.qml"
      },
      __sourceDir: directory + "/araneadev.clock"
    }, "barWidget")
    loader.setSource(entry, {
      moduleName: "araneadev.clock",
      bar: bar
    })
  }
  Component.onCompleted: {
    var directory = Quickshell.env("ARANEA_CLOCK_TEST_PLUGIN_ROOT")
    loadClock(installed, directory)
    loadClock(calendarOnly, directory.replace(/\/plugins$/, "/calendar-plugins"))
    t.step(1800, function () {
      var clock = installed.item
      var p = clock ? clock.clockPanel : null
      t.check(p !== null, "Registry creates the installed Clock panel outside the scanned shell")
      t.check(String(installed.source).indexOf("/external/plugins/") >= 0, "Registry entry point is outside the scanned configuration tree")
      if (!p) {
        t.done()
        return
      }
      t.check(p.weatherPanel !== null && p.worldClockPanel !== null, "external dynamic load constructs both embedded controllers")
      t.check(p.weatherDropdown !== null && p.worldDropdown !== null, "external dynamic load constructs both hosted dropdowns")
      if (p.weatherPanel && p.worldClockPanel) {
        t.check(p.weatherPanel.embedded && p.worldClockPanel.embedded, "optional controllers start in embedded mode")
        t.check(!p.weatherPanel.opened && !p.worldClockPanel.opened, "closed construction leaves optional controllers inactive")
      }
      clock.open()
      t.step(100, function () {
        var frame = t.findChild(p, "clockFrame")
        var calendar = t.findChild(frame, "calendarTab")
        var world = t.findChild(frame, "worldClockTab")
        var weather = t.findChild(frame, "weatherTab")
        t.check(calendar.visible && world.visible && weather.visible, "all three installed tabs are visible")
        t.check(calendar.width > 0 && Math.abs(calendar.width - world.width) < 2 && Math.abs(calendar.width - weather.width) < 2, "installed tabs share the popup width")
        if (p.worldClockPanel && p.weatherPanel && p.worldDropdown && p.weatherDropdown) {
          clock.openSection("worldclock")
          t.check(p.worldClockPanel.opened && p.worldDropdown.visible && p.worldDropdown.implicitHeight > 0, "installed World Clock tab activates its real hosted content")
          clock.openSection("weather")
          t.check(p.weatherPanel.opened && !p.worldClockPanel.opened && p.weatherDropdown.visible && p.weatherDropdown.implicitHeight > 0, "installed Weather tab activates its real hosted content")
        }
        clock.close()
        var fallback = calendarOnly.item ? calendarOnly.item.clockPanel : null
        t.check(fallback !== null, "Calendar loads with both optional plugin directories absent")
        if (fallback) {
          fallback.open()
          t.check(fallback.calendarActive && !fallback.weatherPanel && !fallback.worldClockPanel, "missing optional plugins preserve Calendar")
          t.check(!fallback.selectPage("weather") && !fallback.selectPage("worldclock") && fallback.calendarActive, "unavailable sections retain the working Calendar page")
          fallback.close()
        }
        t.done()
      })
    })
  }
}
