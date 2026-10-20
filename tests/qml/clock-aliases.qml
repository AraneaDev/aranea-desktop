// Trusted production Bar routing: clock sections retain native weather/Elsewhen
// shortcuts, screen selection and exact standalone precedence.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as Bar

ShellRoot {
  id: testRoot
  // Deterministic substitute for the compositor's focused-output observation.
  property string focusedOutput: "B"
  QmlTest {
    id: t
  }
  component ClockEndpoint: QtObject {
    // Observable state at the real Bar's widget-call boundary.
    property bool opened: false
    // Current section, as exposed by the unified clock widget.
    property string activePage: "calendar"
    // Normal clock open selects Calendar.
    function open() {
      openSection("calendar")
    }
    // Widget close dismisses its own popup.
    function close() {
      opened = false
    }
    // Section routing selects a page without a second widget.
    function openSection(page) {
      activePage = page
      opened = true
    }
    // Only the requested visible section counts as open to shell.toggle.
    function isSectionOpen(page) {
      return opened && activePage === page
    }
  }
  component FixtureSlot: Item {
    // Exact registry identity used by production widget lookup.
    property string moduleName
    // Injected widget endpoint; no native window or external operation.
    property var activeItem
    // Native output identity observed at the compositor boundary.
    property var fixtureWindow
    width: 20
    height: 20
  }
  ClockEndpoint {
    id: clockA
  }
  ClockEndpoint {
    id: clockB
  }
  ClockEndpoint {
    id: standalone
  }
  QtObject {
    id: outputA
    // Only the output name is consumed by the production routing algorithm.
    property var screen: ({
        name: "A"
      })
  }
  QtObject {
    id: outputB
    // Distinct focused output for multi-monitor selection.
    property var screen: ({
        name: "B"
      })
  }
  Bar.Bar {
    id: owner
    // Native window lookup is the sole output-boundary adaptation.
    function slotWindow(slot) {
      return slot ? slot.fixtureWindow : null
    }
    // Read the deterministic compositor focus observation.
    function focusedScreenName() {
      return testRoot.focusedOutput
    }
  }
  FixtureSlot {
    id: slotA
    moduleName: "araneadev.clock"
    activeItem: clockA
    fixtureWindow: outputA
  }
  FixtureSlot {
    id: slotB
    moduleName: "araneadev.clock"
    activeItem: clockB
    fixtureWindow: outputB
  }
  FixtureSlot {
    id: exact
    moduleName: "araneadev.weather"
    activeItem: standalone
    fixtureWindow: outputB
  }

  Component.onCompleted: {
    owner.moduleSlots = [slotA, slotB]
    t.check(owner.summonBarWidget("araneadev.weather"), "weather alias opens a clock section")
    t.check(clockB.isSectionOpen("weather") && !clockA.opened, "closed alias opens on the focused output")
    t.check(owner.isBarWidgetOpen("araneadev.weather"), "weather section answers its own open state")
    t.check(!owner.isBarWidgetOpen("araneadev.worldclock"), "a different clock section counts as closed")
    owner.hideBarWidget("araneadev.worldclock")
    t.check(clockB.isSectionOpen("weather"), "hiding an unrelated section leaves weather open")
    owner.hideBarWidget("araneadev.weather")
    t.check(!clockB.opened, "matching section hide closes its visible popup")
    clockA.openSection("calendar")
    t.check(owner.summonBarWidget("omarchy.elsewhen"), "native Elsewhen alias resolves to world clock")
    t.check(clockB.isSectionOpen("worldclock") && clockA.activePage === "calendar", "another page open elsewhere does not steal focused section routing")
    testRoot.focusedOutput = "A"
    owner.hideBarWidget("omarchy.elsewhen")
    t.check(!clockB.opened, "hide finds the visible matching section on the other output")
    clockA.close()
    owner.moduleSlots = [slotA, slotB, exact]
    t.check(owner.summonBarWidget("araneadev.weather"), "standalone weather remains summonable")
    t.check(standalone.opened && !clockA.opened && !clockB.opened, "exact standalone widget wins over clock fallback")
    t.check(owner.isBarWidgetOpen("araneadev.weather"), "standalone open state retains precedence")
    owner.hideBarWidget("araneadev.weather")
    t.check(!standalone.opened, "standalone hide retains precedence")
    t.check(owner.summonBarWidget("omarchy.weather"), "native weather ID finds its configured Aranea standalone")
    t.check(standalone.opened && !clockA.opened && !clockB.opened, "native alias also preserves exact standalone ownership")
    owner.hideBarWidget("omarchy.weather")
    t.check(!standalone.opened, "native alias closes its standalone counterpart")
    t.check(!owner.summonBarWidget("user.unrelated"), "fallback never captures unrelated widget IDs")
    var api = owner.pluginBarApiFor("araneadev.clock", "araneadev.clock", true)
    t.equal(api.moduleWidgets("araneadev.weather").length, 0, "section routing does not broaden facade peer access")
    t.equal(api.moduleWidgets("araneadev.clock").length, 2, "clock facade retains its own output peers")
    t.done()
  }
}
