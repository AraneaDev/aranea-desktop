// Real keyboard and pointer input exercise the shared split action and menu.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: root
  // Signal history from the real split control.
  property var events: []
  // Immutable snapshots exercise the host-owned row model.
  property var choices: [
    {
      kind: 'header',
      label: 'Opens by default'
    },
    {
      kind: 'check',
      key: 'role:editor',
      label: 'Editor',
      checked: true
    },
    {
      kind: 'check',
      key: 'role:agent',
      label: 'Agent',
      checked: false,
      enabled: false,
      tooltip: 'Install Claude Code or Codex to start agents here. This longer explanation must wrap inside the menu without changing its finite width.'
    },
    {
      kind: 'separator'
    },
    {
      kind: 'action',
      key: 'start:codex',
      label: 'Start Codex',
      detail: '10% used',
      enabled: true
    }
  ]
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: 'split-button-input'
    when: false
  }
  FloatingWindow {
    implicitWidth: 480
    implicitHeight: 440
    visible: true
    Aranea.SplitButton {
      id: split
      x: 100
      y: 30
      text: 'Open workspace'
      entries: root.choices
      onClicked: root.events.push('primary')
      onTriggered: function (key) {
        root.events.push(key)
      }
    }
  }
  Component.onCompleted: t.step(100, function () {
    var primary = t.findChild(split, 'splitPrimary')
    var toggle = t.findChild(split, 'splitToggle')
    var menu = t.findChild(split, 'splitMenu')
    Color.popups.background = Qt.rgba(0.1, 0.2, 0.3, 0.4)
    input.mouseClick(primary)
    t.equal(root.events, ['primary'], 'primary pointer click emits the default action')
    toggle.forceActiveFocus()
    input.keyClick(Qt.Key_Down)
    t.check(menu.opened && split.menuOpen && menu.activeFocus, 'Down opens the menu and focuses keyboard input')
    t.equal(menu.fillColor.a, 1, 'in-window menu fill hides competing content underneath')
    t.equal(menu.cursor, 1, 'open selects the first enabled row')
    var rows = t.findChildren(menu, 'menuRow')
    var outline = t.findChild(rows[1], 'cursorOutline')
    t.check(outline.visible && outline.focused && rows[1].visible, 'first keyboard outline is visible immediately')
    t.check(isFinite(menu.width) && menu.width > 0 && isFinite(menu.height) && menu.height > 0, 'popup has finite nonzero dimensions')
    var reason = t.findChild(rows[2], 'menuDetail')
    t.check(reason.visible && reason.height > reason.font.pixelSize * 2 && reason.width > 0 && reason.width < menu.width, 'long disabled reason wraps within fixed menu width')
    menu.move(0)
    t.equal(menu.cursor, 1, 'zero movement leaves selection intact')
    input.keyClick(Qt.Key_Down)
    t.equal(menu.cursor, 4, 'Down skips disabled rows and separators')
    input.keyClick(Qt.Key_Down)
    t.equal(menu.cursor, 4, 'Down clamps at the last enabled row')
    input.keyClick(Qt.Key_Up)
    t.equal(menu.cursor, 1, 'Up skips disabled rows and separators')
    input.keyClick(Qt.Key_J)
    t.equal(menu.cursor, 4, 'j moves down')
    input.keyClick(Qt.Key_K)
    t.equal(menu.cursor, 1, 'k moves up')
    input.keyClick(Qt.Key_Space)
    t.equal(root.events, ['primary', 'role:editor'], 'Space triggers a checkbox choice')
    t.check(menu.opened, 'checkbox activation keeps the menu open')
    input.keyClick(Qt.Key_Return)
    t.equal(root.events[2], 'role:editor', 'Enter also triggers a checkbox choice')
    t.check(menu.opened, 'Enter on a checkbox keeps the menu open')
    input.keyClick(Qt.Key_Down)
    input.keyClick(Qt.Key_Space)
    t.equal(root.events.length, 3, 'Space does not activate an action')
    input.keyClick(Qt.Key_Enter)
    t.equal(root.events[3], 'start:codex', 'Enter activates the selected action')
    t.check(!menu.opened && toggle.activeFocus, 'action closes and restores toggle focus')
    input.keyClick(Qt.Key_Return)
    t.check(menu.opened && menu.activeFocus, 'Enter on the toggle opens the menu')
    input.keyClick(Qt.Key_Escape)
    t.check(!menu.opened && toggle.activeFocus, 'Esc closes and restores toggle focus')
    input.mouseClick(toggle)
    rows = t.findChildren(menu, 'menuRow')
    input.mouseClick(rows[2])
    t.equal(root.events.length, 4, 'disabled row pointer click is inert')
    input.mouseClick(rows[1])
    t.equal(root.events[4], 'role:editor', 'checkbox pointer click emits its key')
    t.check(menu.opened, 'pointer checkbox activation keeps menu open')
    input.mouseClick(rows[4])
    t.equal(root.events[5], 'start:codex', 'action pointer click emits its key')
    t.check(!menu.opened && toggle.activeFocus, 'pointer action closes and restores focus')
    split.enabled = false
    toggle.activate()
    input.mouseClick(toggle)
    input.keyClick(Qt.Key_Down)
    t.check(!menu.opened, 'disabled toggle cannot open menu')
    primary.activate()
    t.equal(root.events.length, 6, 'disabled primary cannot emit activation')
    split.enabled = true
    input.mouseClick(toggle)
    root.choices = [
      {
        kind: 'header',
        label: 'Unavailable'
      },
      {
        kind: 'action',
        key: 'blocked',
        label: 'Blocked',
        enabled: false
      }
    ]
    t.equal(menu.cursor, -1, 'model replacement with no enabled entries clears the cursor')
    input.keyClick(Qt.Key_Down)
    input.keyClick(Qt.Key_Up)
    input.keyClick(Qt.Key_Return)
    input.keyClick(Qt.Key_Space)
    t.equal(root.events.length, 6, 'all-disabled menu input is inert')
    root.choices = [
      {
        kind: 'action',
        key: 'new',
        label: 'New choice'
      }
    ]
    t.equal(menu.cursor, 0, 'new enabled model selects a visible target while open')
    var replacingRow = t.findChildren(menu, 'menuRow')[0]
    input.mousePress(replacingRow)
    root.choices = [
      {
        kind: 'action',
        key: 'replacement',
        label: 'Replacement choice'
      }
    ]
    input.mouseRelease(t.findChildren(menu, 'menuRow')[0])
    t.equal(root.events.length, 6, 'model replacement during a pointer press cannot activate a different choice')
    root.choices = [
      {
        kind: 'action',
        key: 'new',
        label: 'New choice'
      }
    ]

    root.choices = [
      {
        kind: 'check',
        key: 'other',
        label: 'Other',
        checked: false
      },
      {
        kind: 'action',
        key: 'new',
        label: 'New choice'
      }
    ]
    t.equal(menu.cursor, 1, 'model reorder preserves the selected stable key')
    root.choices = [
      {
        kind: 'check',
        key: 'other',
        label: 'Other',
        checked: true
      },
      {
        kind: 'action',
        key: 'new',
        label: 'New choice',
        enabled: false
      }
    ]
    t.equal(menu.cursor, 0, 'disabling the selected entry chooses the first enabled row')
    t.check(root.choices[0].checked, 'menu reads host checked state without mutating the model')
    root.choices = []
    t.equal(menu.cursor, -1, 'empty model clears the cursor')
    menu.move(-1)
    menu.move(0)
    input.keyClick(Qt.Key_Escape)
    t.check(!menu.opened && toggle.activeFocus, 'empty menu still closes with focus return')
    root.choices = [
      {
        kind: 'action',
        key: 'new',
        label: 'New choice'
      }
    ]
    input.keyClick(Qt.Key_Down)
    split.enabled = false
    t.check(!menu.opened, 'disabling the split closes its open menu')
    split.enabled = true
    Aranea.MotionState.motionEnabled = false
    menu.open()
    t.equal(menu.scale, 1, 'reduced motion opens at exact final scale')
    menu.close()
    t.equal(menu.scale, Aranea.DesignTokens.surfaceClosedScale, 'reduced motion closes at exact final scale')
    Aranea.MotionState.motionEnabled = true
    menu.open()
    t.check(menu.scale < 1, 'normal motion starts the shared opening spring')
    t.step(60, function () {
      t.check(menu.scale > Aranea.DesignTokens.surfaceClosedScale, 'opening spring advances toward the final scale')
      Aranea.MotionState.motionEnabled = false
      t.equal(menu.scale, 1, 'reduced motion interrupts an active opening spring exactly')
      t.done()
    })
  })
}
