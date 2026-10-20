// Actual Bar owner/slots and native Indicators; only output windows and helper IO are inert.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.bar" as Bar
import "plugins/araneadev.sudo" as Sudo

ShellRoot {
  id: testRoot
  // Native terminal launch captured through the real scoped bar facade.
  property string launched: ""
  // Refresh requests delivered to the first output.
  property int refreshedA: 0
  // Refresh requests delivered to the second output.
  property int refreshedB: 0
  Window {
    id: stage
    visible: false
    width: 800
    height: 600
  }
  QmlTest {
    id: t
  }
  QtObject {
    id: windowA
    property var screen: ({
        name: "A"
      })
  }
  QtObject {
    id: windowB
    property var screen: ({
        name: "B"
      })
  }
  Component {
    id: sudoComponent
    Sudo.BarWidget {}
  }
  QtObject {
    id: registry
    property var widgets: ({})
    function metadataFor(id) {
      return {
        firstParty: id === "omarchy.indicators"
      }
    }
  }
  Bar.Bar {
    id: barOwner
    barWidgetRegistry: registry
    // Capture terminal requests; the test must never open authentication UI.
    function run(command) {
      testRoot.launched = command
    }
    // Replace only the compositor's window lookup with deterministic outputs.
    function slotWindow(slot) {
      return slot ? slot.fixtureWindow : null
    }
  }
  Bar.BarModuleSlot {
    id: stockA
    owner: barOwner
    property var fixtureWindow: windowA
    entry: ({
        id: "omarchy.indicators",
        items: ["PasswordlessSudo"],
        araneaSudoHostHidden: true
      })
  }
  Bar.BarModuleSlot {
    id: stockB
    owner: barOwner
    property var fixtureWindow: windowB
    entry: ({
        id: "omarchy.indicators",
        items: ["PasswordlessSudo"],
        araneaSudoHostHidden: true
      })
  }
  Bar.BarModuleSlot {
    id: sudoA
    owner: barOwner
    property var fixtureWindow: windowA
    entry: ({
        id: "araneadev.sudo",
        araneaSudoHostHidden: true
      })
  }
  Bar.BarModuleSlot {
    id: sudoB
    owner: barOwner
    property var fixtureWindow: windowB
    entry: ({
        id: "araneadev.sudo"
      })
  }
  Connections {
    target: sudoA.activeItem
    function onRefreshRequested() {
      testRoot.refreshedA++
    }
  }
  Connections {
    target: sudoB.activeItem
    function onRefreshRequested() {
      testRoot.refreshedB++
    }
  }
  Component.onCompleted: {
    stockA.parent = stage.contentItem
    stockB.parent = stage.contentItem
    sudoA.parent = stage.contentItem
    sudoB.parent = stage.contentItem
    var native = Qt.createComponent("file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/bar/widgets/Indicators.qml")
    registry.widgets = ({
        "omarchy.indicators": {
          component: native
        },
        "araneadev.sudo": {
          component: sudoComponent
        }
      })
    t.waitFor(function () {
      return stockA.activeItem && stockB.activeItem && sudoA.activeItem && sudoB.activeItem && sudoA.activeItem.nativeIndicator && sudoB.activeItem.nativeIndicator
    }, 4000, "production registry slots load native indicators and sudo wrappers", function () {
      t.check(String(stockA.activeItem).indexOf("Indicators") >= 0, "refresh source is the real stock Indicators component")
      t.check(stockA.registered && stockA.firstParty, "hidden host is a trusted registry widget")
      t.check(!stockA.visible && stockA.width === 0 && stockA.height === 0, "sole-sudo stock host has no visual or click slot")
      t.check(stockA.activeItem !== null, "hidden stock host remains loaded for native IPC")
      t.check(sudoA.visible && sudoA.width > 0, "hidden-host flag does not hide unrelated third-party widgets")
      var nativeToggle = sudoA.activeItem.nativeIndicator
      t.check(barOwner.pluginOwnsBarObject("araneadev.sudo", nativeToggle), "native button registers through its scoped plugin facade")
      t.check(barOwner.pressModuleClickTarget(sudoA, Qt.LeftButton, sudoA.width / 2, sudoA.height / 2), "real bar hit-testing dispatches the standalone toggle")
      t.equal(testRoot.launched, "omarchy-launch-floating-terminal-with-presentation omarchy-sudo-passwordless", "real bar click captures the native authenticated enable command")
      testRoot.refreshedA = 0
      testRoot.refreshedB = 0
      stockA.activeItem.refresh()
      t.equal(refreshedA, 1, "stock refresh reaches sudo on its own screen")
      t.equal(refreshedB, 0, "stock refresh does not fan out across other screens")
      stockB.activeItem.refresh()
      t.equal(refreshedA, 1, "second screen does not duplicate the first screen refresh")
      t.equal(refreshedB, 1, "second screen refresh reaches its own sudo once")
      barOwner.refreshPasswordlessSudoForSlot({
        registered: true,
        firstParty: false,
        moduleName: "omarchy.indicators",
        fixtureWindow: windowA
      })
      barOwner.refreshPasswordlessSudoForSlot({
        registered: true,
        firstParty: true,
        moduleName: "omarchy.indicators",
        fixtureWindow: null
      })
      t.equal(refreshedA, 1, "untrusted or windowless sources cannot relay")
      var api = barOwner.pluginBarApiFor("araneadev.sudo", "araneadev.sudo", true)
      t.equal(api.moduleWidgets("omarchy.indicators").length, 0, "plugin facade retains its own-id restriction")
      t.equal(api.moduleWidgets("araneadev.sudo").length, 2, "plugin facade still exposes its own monitor peers")
      var old = stockA.activeItem
      var replacement = Qt.createComponent("file://" + Quickshell.env("OMARCHY_PATH") + "/shell/plugins/bar/widgets/Indicators.qml")
      registry.widgets = ({
          "omarchy.indicators": {
            component: replacement
          },
          "araneadev.sudo": {
            component: sudoComponent
          }
        })
      t.waitFor(function () {
        return stockA.activeItem && stockA.activeItem !== old
      }, 4000, "native host hot replacement completes", function () {
        testRoot.refreshedA = 0
        testRoot.refreshedB = 0
        stockA.activeItem.refresh()
        t.equal(refreshedA, 1, "Connections follows the replaced native host exactly once")
        t.equal(refreshedB, 0, "replacement preserves screen-scoped relay")
        stockA.entry = ({
            id: "omarchy.indicators",
            items: ["PasswordlessSudo", "Dnd"],
            araneaSudoHostHidden: true
          })
        t.check(!stockA.hiddenSudoHost && stockA.visible, "a live additional indicator overrides stale hidden metadata")
        stockA.entry = ({
            id: "omarchy.indicators",
            items: ["PasswordlessSudo"]
          })
        t.equal(stockA.hiddenSudoHost, false, "removing flag clears hidden state")
        t.waitFor(function () {
          return stockA.visible && !stockA.hiddenSudoHost
        }, 2000, "removing hidden-host flag restores stock visibility", function () {
          t.done()
        })
      })
    })
  }
}
