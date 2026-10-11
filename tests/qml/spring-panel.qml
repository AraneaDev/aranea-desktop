// Exercises real native panel motion, mask, focus priming and popout handoff.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "lib"
import "plugins/araneadev.shared" as Aranea

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  QtObject {
    id: bar
    property string position: 'top'
    property int barSize: 30
    property var activePopout: null
    property var clickTargets: []
    function requestPopout(owner) {
      if (activePopout && activePopout !== owner)
        activePopout.close()
      activePopout = owner
    }
    function releasePopout(owner) {
      if (activePopout === owner)
        activePopout = null
    }
  }
  FloatingWindow {
    visible: true
    width: 1000
    height: 30
    Item {
      id: anchor
      width: 20
      height: 20
      x: 300
    }
  }
  FloatingWindow {
    visible: true
    width: 1000
    height: 800
    Aranea.SpringPanel {
      id: panel
      motionEnabled: true
      anchorItem: anchor
      bar: bar
      contentWidth: 300
      contentHeight: 200
      focusTarget: target
      Item {
        id: target
        anchors.fill: parent
      }
    }
  }
  FloatingWindow {
    visible: true
    width: 1000
    height: 800
    Aranea.SpringPanel {
      id: sibling
      motionEnabled: false
      anchorItem: anchor
      bar: bar
    }
  }
  Component.onCompleted: t.step(50, function () {
    t.equal(panel.mask.width, 0, 'closed native surface has empty pointer region')
    panel.open = true
    t.check(bar.activePopout === panel, 'logical open acquires coordinator')
    t.equal(panel.mask.width, panel.screenW, 'open native surface acquires pointer region')
    t.check(!panel.focusPrimed, 'opening begins exclusive focus prime')
    t.equal(panel.nativeLayer.keyboardFocus, WlrKeyboardFocus.Exclusive, 'open requests native exclusive focus')
    t.equal(panel.cardOrigin.y, panel.barH + panel.gap, 'top placement preserves native bar edge')
    t.step(100, function () {
      t.check(panel.focusPrimed, 'focus prime settles to on-demand')
      t.equal(panel.nativeLayer.keyboardFocus, WlrKeyboardFocus.OnDemand, 'settled native focus permits multi-screen dismissal')
      var card = t.findChild(panel, 'springPanelCard')
      t.check(card.opacity > 0 && card.opacity <= 1, 'native card fades as one surface')
      panel.close()
      t.equal(bar.activePopout, null, 'logical close releases coordinator immediately')
      t.equal(panel.mask.width, 0, 'closing native surface immediately releases pointer region')
      t.equal(panel.mask.height, 0, 'closing native surface empties pointer region in both axes')
      t.equal(panel.nativeLayer.keyboardFocus, WlrKeyboardFocus.None, 'closing native surface immediately releases keyboard')
      t.check(!target.enabled, 'closing content rejects stale clicks and keys')
      t.check(panel.visible, 'closing card retains decorative presentation')
      var opacity = card.opacity
      panel.open = true
      t.equal(card.opacity, opacity, 'reopen continues current presentation')
      t.equal(panel.nativeLayer.keyboardFocus, WlrKeyboardFocus.Exclusive, 'reopening mapped surface primes focus again')
      panel.motionEnabled = false
      t.equal(card.opacity, 1, 'reduced motion snaps open card')
      t.equal(card.scale, 1, 'reduced motion snaps spatial state')
      panel.close()
      t.check(!panel.visible, 'reduced motion close unmaps immediately')
      t.equal(panel.mask.width, 0, 'reduced motion close releases input')
      panel.open = true
      sibling.open = true
      t.check(!panel.open && sibling.open, 'single popout switching closes previous logical panel')
      t.check(bar.activePopout === sibling, 'switching transfers coordinator ownership')
      t.check(!panel.visible && sibling.visible, 'reduced motion switching is immediate')
      panel.close()
      t.check(bar.activePopout === sibling, 'old panel close cannot release sibling ownership')
      sibling.close()
      t.equal(bar.activePopout, null, 'sibling close releases its ownership')
      t.done()
    })
  })
}
