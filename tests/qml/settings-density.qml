// Real Settings controls keep compact geometry, visible focus and guarded actions.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.settings" as Settings
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: root
  // Actions emitted by the real button, including its keyboard path.
  property int actions: 0
  QmlTest {
    id: t
  }
  TestCase {
    id: keyboard
    name: 'settings-density-keyboard'
    when: false
  }
  FloatingWindow {
    implicitWidth: 420
    implicitHeight: 280
    visible: true
    Item {
      id: host
      anchors.fill: parent
      Settings.SettingsButton {
        id: action
        objectName: 'compactAction'
        x: 12
        y: 12
        text: 'Apply'
        onClicked: root.actions++
      }
      Settings.SettingsToggle {
        id: toggle
        x: 160
        y: 12
      }
      Aranea.FilamentPill {
        id: shared
        x: 240
        y: 12
        text: 'Shared'
      }
      Settings.SettingsNavigation {
        id: navigation
        x: 12
        y: 70
        width: Style.space(148)
      }
    }
  }
  Component.onCompleted: t.step(50, function () {
    var button = t.findChild(host, 'compactAction')
    t.check(button.implicitHeight === Style.space(28), 'compact action height')
    t.check(button.implicitWidth < Style.space(92), 'short action has no oversized minimum')
    var shortWidth = button.implicitWidth
    button.text = 'Apply wallpaper'
    t.check(button.implicitWidth > shortWidth, 'action width follows its content')
    t.equal(toggle.implicitWidth, Style.space(34), 'switch keeps compact visible width')
    t.equal(toggle.implicitHeight, Style.space(16), 'switch keeps compact visible height')
    t.check(button.variant !== undefined, 'Settings action exposes presentation variants')
    if (button.variant !== undefined) {
      t.equal(button.variant, 'secondary', 'ordinary action defaults to secondary')
      t.check(!t.findChild(button, 'pillBorder').visible, 'ordinary action keeps a quiet surface')
      button.variant = 'quiet'
      t.check(!t.findChild(button, 'pillBorder').visible, 'quiet action has no persistent border')
      button.variant = 'primary'
      t.check(t.findChild(button, 'selectedFill').visible, 'primary action retains accent emphasis')
    }
    var categories = t.findChildren(navigation, 'pill')
    t.equal(categories.length, 6, 'Projects and existing destinations remain available')
    t.equal(navigation.categories.map(function (category) {
      return category.id
    }).sort(), ['appearance', 'display', 'integrations', 'notifications', 'projects', 'schedule'], 'all settings destinations retain stable identities')
    for (var i = 0; i < categories.length; i++) {
      t.check(!t.findChild(categories[i], 'pillBorder').visible, 'navigation has no persistent full border ' + i)
      t.check(!!t.findChild(categories[i], 'navigationIcon'), 'navigation has an icon ' + i)
    }
    t.check(t.findChild(shared, 'pillBorder').visible, 'shared pill keeps its default border')
    shared.selected = true
    t.check(t.findChild(shared, 'pillUnderline').visible, 'shared pill keeps selected underline')
    button.forceActiveFocus()
    t.check(t.findChild(button, 'cursorOutline').border.width > 0, 'keyboard focus remains visible')
    keyboard.keyClick(Qt.Key_Space)
    t.equal(actions, 1, 'keyboard activates compact action')
    button.enabled = false
    button.activate()
    keyboard.keyClick(Qt.Key_Return)
    t.equal(actions, 1, 'disabled action stays guarded')
    navigation.compact = true
    navigation.width = Style.space(320)
    t.step(20, function () {
      categories = t.findChildren(navigation, 'pill')
      t.check(categories[0].y === categories[1].y && categories[2].y > categories[0].y, 'compact navigation keeps two columns')
      t.check(categories[1].x + categories[1].width <= navigation.width, 'compact navigation stays within host width')
      t.done()
    })
  })
}
