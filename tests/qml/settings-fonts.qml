// Real font drafts, searchable role choices and guarded explicit application.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Number of real section mutation requests.
  property int requests: 0
  // Latest operation and exact role arguments.
  property var last: []
  QmlTest {
    id: t
  }
  Settings.FontsSection {
    id: fonts
    width: 300
    fonts: ({
        uiFamily: "Example Sans",
        technicalFamily: "Example Mono",
        availability: "available",
        families: ["Example Sans", "Example Mono"],
        monospaceFamilies: ["Example Mono"]
      })
    onRequest: function (operation, args) {
      root.requests++
      root.last = [operation, args]
    }
  }
  Settings.FontSelector {
    id: selector
    width: 280
    families: ["Example Sans", "Example Mono", "Second Sans"]
    onChosen: function (family) {
      fonts.uiDraft = family
      fonts.dirty = true
    }
  }
  Component.onCompleted: t.step(20, function () {
    t.equal(fonts.uiDraft, "Example Sans", "initial draft adopts owner")
    selector.query = "second"
    t.equal(selector.filteredFamilies, ["Second Sans"], "search filters case-insensitively")
    selector.choose("Second Sans")
    t.equal(root.requests, 0, "selecting a family does not apply")
    fonts.resetDraft()
    t.equal([fonts.uiDraft, fonts.technicalDraft], ["", ""], "reset drafts defaults")
    t.equal(root.requests, 0, "reset requires explicit Apply")
    fonts.applyFonts()
    t.equal(root.last, ["configure fonts", ["", ""]], "Apply emits exact default role arguments")
    fonts.pending = true
    fonts.applyFonts()
    t.equal(root.requests, 1, "pending mutation cannot apply again")
    fonts.pending = false
    fonts.displayOnly = true
    fonts.applyFonts()
    t.equal(root.requests, 1, "inert showcase cannot mutate")
    fonts.displayOnly = false
    fonts.fonts = ({
        availability: "unavailable"
      })
    fonts.applyFonts()
    t.equal(root.requests, 1, "unavailable owner cannot apply")
    t.check(fonts.implicitHeight > 0, "narrow font controls retain scrollable height")
    t.done()
  })
}
