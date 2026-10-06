// Disclosure keeps expansion in its host and drops all hidden content height.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import qs.Ui
import "lib"
import "plugins/araneadev.shared" as Shared

ShellRoot {
  QmlTest {
    id: t
  }

  // Toggle requests recorded without changing the expansion state.
  property int requests: 0
  // Heading height captured before expanding the detail content.
  property real collapsedHeight: 0

  TestCase {
    id: pointer
    name: "pointer"
    when: false
  }

  FloatingWindow {
    implicitWidth: 400
    implicitHeight: 300
    visible: true

    Item {
      id: stage
      anchors.fill: parent

      PointerMoveGate {
        id: gate
        property real layoutChangedAt: 0
        referenceItem: stage
      }

      Shared.DisclosureSection {
        id: section
        width: 360
        title: "Resource details"
        pointerGate: gate
        onToggleRequested: requests += 1

        Item {
          id: details
          width: parent.width
          height: 100
        }
      }
    }
  }

  Component.onCompleted: t.step(400, function () {
    var heading = t.findChild(section, "disclosureHeading")
    collapsedHeight = section.height
    t.check(collapsedHeight > 0 && collapsedHeight < 100, "collapsed section retains only its heading")
    t.check(!details.visible, "collapsed content is hidden")
    pointer.mouseClick(heading, 40, heading.height / 2)
    t.equal(requests, 1, "one heading click emits exactly one toggle request")
    t.check(!section.expanded, "pointer activation leaves expansion owned by the host")
    section.expanded = true

    t.step(50, function () {
      t.check(details.visible, "host expansion shows the content")
      t.equal(section.height, collapsedHeight + 100 + Style.space(16), "expanded section includes content and section spacing")
      var indicator = t.findChild(section, "disclosureIndicator")
      var expandedIndicator = indicator.text
      section.expanded = false

      t.step(50, function () {
        t.equal(section.height, collapsedHeight, "collapsing removes all content height and its gap")
        t.check(indicator.text !== expandedIndicator, "heading indicates expanded and collapsed state")
        section.activate()
        t.equal(requests, 2, "keyboard activation emits exactly one request")
        t.check(!section.expanded, "keyboard activation leaves expansion owned by the host")
        var outline = t.findChild(section, "cursorOutline")
        t.equal(outline.border.width, 0, "pointer interaction never draws a mint outline")
        section.keyboardFocused = true
        t.check(outline.border.width > 0, "host keyboard focus draws a visible outline")
        t.check(Qt.colorEqual(outline.border.color, Shared.DesignTokens.accent), "keyboard outline uses mint")
        section.keyboardFocused = false

        gate.layoutChangedAt = Date.now()
        pointer.mouseClick(t.findChild(section, "disclosureHeading"), 40, collapsedHeight / 2)
        t.equal(requests, 2, "fresh layout stamp refuses stale pointer clicks")
        t.step(350, function () {
          pointer.mouseClick(t.findChild(section, "disclosureHeading"), 40, collapsedHeight / 2)
          t.equal(requests, 3, "settled heading accepts pointer clicks again")
          t.done()
        })
      })
    })
  })
}
