// Explicit candidate and related-worktree selection, separate from registration.
pragma ComponentBehavior: Bound
import QtQuick
import "../araneadev.shared" as Aranea
import QtQuick.Layouts
import qs.Commons

ColumnLayout {
  id: list
  // Read-only discovery observations, grouped by repository common directory.
  property var candidates: []
  // Exact checkout paths explicitly selected for Add selected.
  property var selectedPaths: []
  // Already approved checkout members stay separate from selectable review paths.
  property var registeredPaths: []
  // Disable every action during inert capture or another registry mutation.
  property bool displayOnly: false
  // Shared pointer/layout settling gate.
  property var pointerGate: null
  // Candidate groups preserve duplicate names and location context.
  readonly property var groups: candidates
  // Ignore applies to the repository's durable common-directory group.
  signal ignoreRequested(string path)
  // Enumerate each discovered checkout once, including external worktrees.
  function paths(candidate: var): var {
    var result = [
      {
        path: candidate.path,
        branch: '',
        primary: true
      }
    ]
    var checkouts = candidate.checkouts || []
    for (var i = 0; i < checkouts.length; i++) {
      if (checkouts[i].path === candidate.path)
        result[0] = checkouts[i]
      else if (!result.some(function (c) {
        return c.path === checkouts[i].path
      }))
        result.push(checkouts[i])
    }
    return result.filter(function (checkout) {
      return list.registeredPaths.indexOf(checkout.path) < 0
    })
  }
  // Candidate selection changes presentation only, never the registry.
  function select(path: string, selected: bool): void {
    if (displayOnly)
      return
    var known = candidates.some(function (c) {
      return paths(c).some(function (p) {
        return p.path === path
      })
    })
    if (!known)
      return
    var next = selectedPaths.filter(function (p) {
      return p !== path
    })
    if (selected)
      next.push(path)
    selectedPaths = next
  }
  // Remove selected members after backend approval without discarding their siblings.
  function reconcileSelection(): void {
    selectedPaths = selectedPaths.filter(function (path) {
      return candidates.some(function (c) {
        return paths(c).some(function (p) {
          return p.path === path
        })
      })
    })
  }
  onCandidatesChanged: reconcileSelection()
  onRegisteredPathsChanged: reconcileSelection()
  spacing: Style.space(12)
  Repeater {
    model: list.groups
    ColumnLayout {
      id: group
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(4)
      Aranea.UiLabel {
        Layout.fillWidth: true
        text: group.modelData.name
        font.bold: true
      }
      Repeater {
        model: list.paths(group.modelData)
        RowLayout {
          id: checkout
          required property var modelData
          Layout.fillWidth: true
          Aranea.ActionToggle {
            checked: list.selectedPaths.indexOf(checkout.modelData.path) >= 0
            enabled: !list.displayOnly
            pointerGate: list.pointerGate
            Accessible.name: 'Select ' + checkout.modelData.path
            onToggled: list.select(checkout.modelData.path, !checked)
          }
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: checkout.modelData.path + (checkout.modelData.branch ? ' · ' + checkout.modelData.branch : '')
          }
        }
      }
      Aranea.ActionButton {
        text: 'Ignore'
        enabled: !list.displayOnly
        pointerGate: list.pointerGate
        onClicked: list.ignoreRequested(group.modelData.path)
      }
    }
  }
}
