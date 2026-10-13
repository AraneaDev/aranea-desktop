// Project rows and pin controls retain exact keyboard focus through model publication.
import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 500
    implicitHeight: 600
    Projects.ProjectsSidebar {
      id: sidebar
      width: 260
      height: 360
    }
    TextField {
      id: externalField
      x: 280
      width: 200
      placeholderText: 'Configuration draft'
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    var projects = []
    for (var i = 0; i < 10; i++)
      projects.push({
        id: 'p-' + i,
        name: 'Project ' + i,
        lastCheckoutId: 'c-' + i,
        checkouts: [
          {
            id: 'c-' + i,
            path: '/work/' + i,
            branch: 'main'
          }
        ]
      })
    sidebar.projects = projects
    sidebar.query = 'Project'
    t.step(80, function () {
      var row = t.findChild(sidebar, 'selectProject:p-2')
      row.forceActiveFocus()
      t.check(row.activeFocus, 'row holds keyboard focus before metadata publication')
      sidebar.scrollTo(240)
      var y = sidebar.contentY
      sidebar.navigation = {
        pinnedProjectIds: ['p-8'],
        visitedAt: {
          'p-7': 1000
        }
      }
      t.step(80, function () {
        var refreshed = t.findChild(sidebar, 'selectProject:p-2')
        t.check(refreshed.activeFocus, 'row retains keyboard focus across metadata refresh')
        t.equal(sidebar.contentY, y, 'focused-row metadata refresh retains the viewport')
        var pin = t.findChild(sidebar, 'pinProject:p-5')
        pin.forceActiveFocus()
        t.check(pin.activeFocus, 'pin button holds keyboard focus before metadata publication')
        sidebar.navigation = {
          pinnedProjectIds: ['p-5', 'p-8'],
          visitedAt: {
            'p-7': 2000
          }
        }
        t.step(80, function () {
          t.check(t.findChild(sidebar, 'pinProject:p-5').activeFocus, 'exact pin button retains keyboard focus across pin metadata refresh')
          sidebar.projects = projects.map(function (project) {
            return Object.assign({}, project, {
              name: project.name + ' refreshed'
            })
          })
          t.step(80, function () {
            t.check(t.findChild(sidebar, 'pinProject:p-5').activeFocus, 'exact pin button retains focus across registry replacement')
            sidebar.query = ''
            sidebar.navigation = {
              pinnedProjectIds: ['p-8'],
              visitedAt: {
                'p-7': 3000
              }
            }
            t.step(80, function () {
              t.equal(sidebar.filteredProjects.slice(0, 2).map(function (row) {
                return row.id
              }), ['p-8', 'p-7'], 'unfrozen results genuinely reorder after pin and recency changes')
              t.check(t.findChild(sidebar, 'pinProject:p-5').activeFocus, 'pin focus follows exact identity when ranking moves its row')
              sidebar.focusSearch()
              sidebar.navigation = {
                pinnedProjectIds: ['p-1'],
                visitedAt: {}
              }
              t.step(80, function () {
                t.check(t.findChild(sidebar, 'projectSearch').activeFocus, 'metadata refresh leaves search focus untouched')
                externalField.forceActiveFocus()
                sidebar.navigation = {
                  pinnedProjectIds: ['p-9'],
                  visitedAt: {}
                }
                t.step(80, function () {
                  t.check(externalField.activeFocus, 'metadata refresh never steals an unrelated field focus')
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  }
}
