// Keyboard panels sized by their content: the update center and the
// workspace overview end with their last row and keep the layout spacing
// between rows, whatever the number of rows. A long list is capped, through
// a single host-owned maxContentHeight, so it can't push the panel past the
// host's maximum popup height; the workspace list also keeps the keyboard
// cursor scrolled into view.
import QtQuick
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.updates" as Updates
import "plugins/araneadev.workspaces" as Workspaces
import "plugins/araneadev.shared" as Shared

ShellRoot {
  QmlTest {
    id: t
  }

  // Modeled after KeyboardPanel.qml's own padding/border, since a real
  // KeyboardPanel host can't easily load offscreen in this test.
  // The popup padding applied on every side.
  readonly property real popupPadding: Style.spacing.popupPadding
  // The card's border width (top and bottom both use this).
  readonly property real borderWidth: Shared.DesignTokens.borderWidth
  // Total non-content height the card always reserves: padding top and
  // bottom, plus border top and bottom.
  readonly property real verticalContentInset: popupPadding * 2 + borderWidth * 2

  // A host on a big screen: KeyboardPanel.availableCardHeight exceeds
  // Style.space(520), so the card's own cap (520) binds.
  readonly property real bigScreenCardCap: Math.min(Style.space(520), 2000)
  // A host on a small screen: availableCardHeight is under 520, so the
  // screen (not the 520 constant) binds instead.
  readonly property real smallScreenCardCap: Math.min(Style.space(520), 300)

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

  // Long lists, and every maxContentHeight scenario, are fixed at
  // construction (never reassigned later): this file has no real Window,
  // and without one this Quickshell/Qt combination only ever resolves a
  // Layout's own implicitHeight/preferredHeight chain during the very
  // first layout pass - a later Repeater model or plain property change
  // that should reflow a ColumnLayout never takes effect in this offscreen
  // harness. That's a test-only quirk (verified against a real Window,
  // where it lays out correctly), not a production bug: the real host is a
  // real layer-shell window with a running render loop. So instead of
  // mutating one instance across scenarios, each scenario gets its own
  // panel, fully configured from the start.
  Updates.UpdatePanel {
    id: manyUpdatesBigScreen
    status: ({
        count: 40,
        groups: fakeGroups(40),
        checkedAt: 0
      })
    maxContentHeight: bigScreenCardCap - verticalContentInset
  }

  Updates.UpdatePanel {
    id: manyUpdatesSmallScreen
    status: ({
        count: 40,
        groups: fakeGroups(40),
        checkedAt: 0
      })
    maxContentHeight: smallScreenCardCap - verticalContentInset
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
    id: manyWorkspacesBigScreen
    workspaceStates: fakeWorkspaces(20)
    maxContentHeight: bigScreenCardCap - verticalContentInset
  }

  Workspaces.WorkspacePanel {
    id: manyWorkspacesSmallScreen
    workspaceStates: fakeWorkspaces(20)
    maxContentHeight: smallScreenCardCap - verticalContentInset
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

  // Asserts a long-list panel obeys the single host-owned cap: its content
  // never exceeds maxContentHeight, and, critically, the card the host would
  // draw around it (content + verticalContentInset) never exceeds
  // cardCap: the two caps this fix reconciled can no longer disagree.
  function checkCapRelationship(panel, cardCap, name) {
    t.check(panel.height <= panel.maxContentHeight + 0.5, name + ": content is capped at its maxContentHeight")
    t.check(panel.height + verticalContentInset <= cardCap + 0.5, name + ": content + card padding/border never exceeds the host's card cap")
  }

  Component.onCompleted: t.step(50, function () {
    checkPacked(updates, Style.space(8), "update center")
    checkPacked(quietUpdates, Style.space(8), "update center without groups")
    checkPacked(workspaces, Style.space(8), "workspace overview")

    // Long lists, big screen (the 520 constant binds): the panel stays
    // packed (no dead gaps appear from capping) and never grows past the
    // host's maximum popup height.
    checkPacked(manyUpdatesBigScreen, Style.space(8), "update center (40 groups, big screen)")
    checkPacked(manyWorkspacesBigScreen, Style.space(8), "workspace overview (20 rows, big screen)")
    checkCapRelationship(manyUpdatesBigScreen, bigScreenCardCap, "40 updates, big screen")
    checkCapRelationship(manyWorkspacesBigScreen, bigScreenCardCap, "20 workspaces, big screen")
    // Uncapped, 40 groups / 20 rows would clearly exceed the cap, so a
    // passing check above proves the cap actually engaged.
    t.check(manyUpdatesBigScreen.height < Style.space(210) + 40 * Style.space(32), "40 updates: cap is below the naive uncapped estimate")
    t.check(manyWorkspacesBigScreen.height < Style.space(154) + 20 * Style.space(58), "20 workspaces: cap is below the naive uncapped estimate")

    // Long lists, small screen (availableCardHeight, not the 520 constant,
    // binds): the same relationship must hold with a tighter cap.
    checkPacked(manyUpdatesSmallScreen, Style.space(8), "update center (40 groups, small screen)")
    checkPacked(manyWorkspacesSmallScreen, Style.space(8), "workspace overview (20 rows, small screen)")
    checkCapRelationship(manyUpdatesSmallScreen, smallScreenCardCap, "40 updates, small screen")
    checkCapRelationship(manyWorkspacesSmallScreen, smallScreenCardCap, "20 workspaces, small screen")
    t.check(smallScreenCardCap < bigScreenCardCap, "small screen cap is actually the tighter one (sanity)")

    // Keyboard selection must stay scrolled into view: move the cursor to
    // the last of the 20 (still capped to the small-screen height, so most
    // rows are scrolled out) and confirm it's visible, and that the first
    // row (no longer the cursor) has scrolled out of view. cursorIndex only
    // recolors the highlighted row and moves the Flickable's contentY - it
    // never needs a Layout to reflow - so it works fine without a real
    // window.
    manyWorkspacesSmallScreen.cursorIndex = 19
    t.step(50, function () {
      t.check(manyWorkspacesSmallScreen.isRowVisible(19), "cursor moved to the last workspace row: it scrolls into view")
      t.check(!manyWorkspacesSmallScreen.isRowVisible(0), "cursor moved to the last workspace row: the first row scrolls out of view")
      t.done()
    })
  })
}
