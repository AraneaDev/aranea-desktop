// Keyboard panels sized by their content: the update center and the
// workspace overview end with their last row and keep the layout spacing
// between rows, whatever the number of rows. A long list is capped so it
// can't push the panel past the host's maximum popup height.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.updates" as Updates
import "plugins/araneadev.workspaces" as Workspaces

ShellRoot {
  QmlTest {
    id: t
  }

  // Maximum popup height both panels intrinsically cap themselves at,
  // matching the host's old Math.min(Style.space(520), ...) cap.
  readonly property real maxHeight: Style.space(520)

  Updates.UpdatePanel {
    id: updates
    status: ({
        count: 2,
        rebootRequired: true,
        groups: [
          {
            source: "system",
            count: 1
          },
          {
            source: "flatpak",
            count: 1
          }
        ],
        checkedAt: 0
      })
  }

  Updates.UpdatePanel {
    id: quietUpdates
    status: ({
        count: 0,
        groups: []
      })
  }

  Updates.UpdatePanel {
    id: manyUpdates
  }

  Workspaces.WorkspacePanel {
    id: workspaces
    workspaceStates: [
      {
        id: 1,
        name: "1",
        windows: 1,
        active: true,
        urgent: false,
        windowLabels: ["kitty"]
      },
      {
        id: 2,
        name: "2",
        windows: 0,
        active: false,
        urgent: false,
        windowLabels: []
      }
    ]
  }

  Workspaces.WorkspacePanel {
    id: manyWorkspaces
  }

  // Visible children of LAYOUT with a height, top to bottom (skips the Repeater).
  function laidOut(layout) {
    var kids = []
    for (var i = 0; i < layout.children.length; i++) {
      var kid = layout.children[i]
      if (kid.visible && kid.height > 0)
        kids.push(kid)
    }
    return kids.sort(function (a, b) {
      return a.y - b.y
    })
  }

  // PANEL's content starts at its top, keeps SPACING between children and ends at its bottom.
  function checkPacked(panel, spacing, name) {
    var kids = laidOut(panel.children[0])
    t.equal(Math.round(kids[0].y), 0, name + ": content starts at the top")
    for (var i = 1; i < kids.length; i++)
      t.equal(Math.round(kids[i].y - kids[i - 1].y - kids[i - 1].height), spacing, name + ": gap " + i + " is the layout spacing")
    var last = kids[kids.length - 1]
    t.equal(Math.round(last.y + last.height), Math.round(panel.height), name + ": the panel ends with its content")
  }

  // Builds N synthetic update groups.
  function fakeGroups(n) {
    var groups = []
    for (var i = 0; i < n; i++)
      groups.push({
        source: "source-" + i,
        count: i + 1
      })
    return groups
  }

  // Builds N synthetic workspace rows.
  function fakeWorkspaces(n) {
    var rows = []
    for (var i = 0; i < n; i++)
      rows.push({
        id: i + 1,
        name: String(i + 1),
        windows: i,
        active: i === 0,
        urgent: false,
        windowLabels: []
      })
    return rows
  }

  Component.onCompleted: t.step(50, function () {
    checkPacked(updates, Style.space(8), "update center")
    checkPacked(quietUpdates, Style.space(8), "update center without groups")
    checkPacked(workspaces, Style.space(8), "workspace overview")

    // Long lists: the panel stays packed (no dead gaps appear from capping)
    // and never grows past the host's maximum popup height.
    manyUpdates.status = ({
        count: 40,
        groups: fakeGroups(40),
        checkedAt: 0
      })
    manyWorkspaces.workspaceStates = fakeWorkspaces(20)

    t.step(50, function () {
      checkPacked(manyUpdates, Style.space(8), "update center (40 groups)")
      checkPacked(manyWorkspaces, Style.space(8), "workspace overview (20 rows)")
      t.check(manyUpdates.height <= maxHeight + 0.5, "40 updates: panel height is capped at " + maxHeight)
      t.check(manyWorkspaces.height <= maxHeight + 0.5, "20 workspaces: panel height is capped at " + maxHeight)
      // Uncapped, 40 groups / 20 rows would clearly exceed the cap, so a
      // passing check above proves the cap actually engaged.
      t.check(manyUpdates.height < Style.space(210) + 40 * Style.space(32), "40 updates: cap is below the naive uncapped estimate")
      t.check(manyWorkspaces.height < Style.space(154) + 20 * Style.space(58), "20 workspaces: cap is below the naive uncapped estimate")
      t.done()
    })
  })
}
