// Search navigation exercises the production list and picker without launching tools.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  // Exact inspected identity recorded at the host boundary.
  property string selectedId: ''
  // Selection signals independently counted for duplicate activation.
  property var selections: []
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: 'pickerInput'
    when: false
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 500
    implicitHeight: 620
    Item {
      id: canvas
      anchors.fill: parent
    }
  }
  Projects.ProjectsSidebar {
    id: sidebar
    parent: canvas
    width: 260
    height: 420
    onProjectRequested: function (id) {
      host.selectedId = id
      host.selections.push(id)
    }
  }
  // Independent registry fixtures cover scale and duplicate display names.
  function projects(count) {
    var result = []
    for (var i = 0; i < count; i++)
      result.push({
        id: 'p-' + i,
        name: i === 72 || i === 73 ? 'Duplicate' : 'Project ' + String(i).padStart(3, '0') + (i === 99 ? ' with a very long repository name'.repeat(8) : ''),
        lastCheckoutId: 'c-' + i,
        checkouts: [
          {
            id: 'c-' + i,
            path: '/work/' + i + (i === 99 ? '/a-very-long-parent-directory'.repeat(8) : '') + '/repo',
            branch: 'main'
          },
          {
            id: 'b-' + i,
            path: '/work/alternate-' + i,
            branch: 'feature-' + i
          }
        ]
      })
    return result
  }
  Component.onCompleted: t.step(80, function () {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    sidebar.projects = projects(100)
    sidebar.query = 'feature-73'
    t.equal(sidebar.filteredProjects.map(function (p) {
      return p.id
    }), ['p-73'], 'search includes unselected checkout branches')
    var component = Qt.createComponent('plugins/araneadev.projects/ProjectPicker.qml')
    t.check(component.status === Component.Ready, 'searchable picker is available for narrow project navigation')
    if (component.status !== Component.Ready) {
      t.done()
      return
    }
    var picker = component.createObject(canvas, {
      objectName: 'testPicker',
      width: 450,
      height: 520
    })
    picker.selected.connect(function (id) {
      host.selectedId = id
      host.selections.push(id)
    })
    var dismissed = 0
    picker.dismissed.connect(function () {
      dismissed++
    });
    [0, 1, 10, 50, 100].forEach(function (count) {
      sidebar.query = ''
      sidebar.projects = projects(count)
      picker.rows = sidebar.filteredProjects
      t.equal(picker.rows.length, count, 'all ' + count + ' registered projects remain searchable')
    })
    picker.open()
    t.step(80, function () {
      t.check(picker.opened, 'picker opens with a complete searchable list')
      var list = t.findChild(picker, 'pickerList')
      list.query = '/work/73/'
      t.equal(list.filteredProjects.map(function (p) {
        return p.id
      }), ['p-73'], 'duplicate names disambiguate by exact checkout path')
      list.focusSearch()
      input.keyClick(Qt.Key_Down)
      input.keyClick(Qt.Key_Return)
      t.equal(host.selectedId, 'p-73', 'arrow and Enter inspect the exact matching identity')
      t.equal(host.selections, ['p-73'], 'keyboard activation selects exactly once')
      t.check(!picker.opened, 'selection dismisses the narrow picker')
      picker.pinningEnabled = true
      var pins = []
      picker.pinRequested.connect(function (id, pinned) {
        pins.push([id, pinned])
      })
      picker.open()
      t.findChild(list, 'pinProject:p-73').activate()
      t.equal(pins, [['p-73', true]], 'quiet pin action retains the exact row identity')
      t.equal(host.selections, ['p-73'], 'pinning does not select or launch a project')
      t.check(picker.opened, 'pinning keeps the chooser available')
      picker.open()
      list.query = 'absent'
      t.equal(list.filteredProjects.length, 0, 'empty search retains an explicit reset action')
      t.findChild(list, 'resetProjectQuery').activate()
      t.equal(picker.query, '', 'query reset restores the complete list')
      list.focusSearch()
      input.keyClick(Qt.Key_Escape)
      t.check(!picker.opened, 'Escape dismisses the picker')
      t.check(dismissed > 0, 'picker exposes dismissal to its host')
      picker.displayOnly = true
      picker.open()
      t.check(!picker.opened, 'inert previews refuse picker activation')
      sidebar.query = 'project'
      var before = sidebar.filteredProjects.map(function (p) {
        return p.id
      })
      sidebar.focusSearch()
      input.keyClick(Qt.Key_Down)
      sidebar.navigation = {
        pinnedProjectIds: ['p-99'],
        visitedAt: {
          'p-98': 1000
        }
      }
      t.equal(sidebar.filteredProjects.map(function (p) {
        return p.id
      }), before, 'metadata refresh cannot reorder active query navigation')
      t.equal(sidebar.highlightedId, 'p-0', 'refresh retains the exact keyboard cursor identity')
      sidebar.selectedId = 'p-73'
      sidebar.query = ''
      t.step(80, function () {
        sidebar.scrollTo(600)
        var y = sidebar.contentY
        sidebar.projects = projects(100)
        t.step(80, function () {
          t.equal(sidebar.selectedId, 'p-73', 'registry refresh preserves selected identity')
          t.equal(sidebar.contentY, y, 'registry refresh preserves project viewport')
          var longRow = t.findChild(sidebar, 'selectProject:p-99'), normalRow = t.findChild(sidebar, 'selectProject:p-98')
          t.equal(longRow.height, normalRow.height, 'long names and paths retain compact row height at 100 projects')
          t.check(t.findChild(longRow, 'projectRowName').truncated, 'long list names elide instead of growing the row')
          t.check(longRow.fullLabel.indexOf(' with a very long repository name'.repeat(8)) >= 0 && longRow.fullLabel.indexOf('/a-very-long-parent-directory'.repeat(8)) >= 0, 'hover and accessibility retain the complete long name and checkout path')
          t.done()
        })
      })
    })
  })
}
