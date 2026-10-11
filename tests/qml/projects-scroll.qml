// Real wheel and keyboard input must reach both Projects viewports.
import QtQuick
import QtTest
import Quickshell
import qs.Commons
import "lib"
import "plugins/araneadev.projects" as Projects

ShellRoot {
  id: host
  QmlTest {
    id: t
  }
  TestCase {
    id: input
    name: 'projectsInput'
    when: false
  }
  Projects.ProjectsPresentation {
    id: entry
    windowEnabled: false
  }
  FloatingWindow {
    id: window
    visible: true
    implicitWidth: 960
    implicitHeight: 540
    Projects.ProjectsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: {
    entry.view = surface
    entry.projectController.captureActive = true
    entry.projectClient.captureActive = true
    entry.discoveryClient.captureActive = true
    entry.activityClient.captureActive = true
    t.findChild(surface, 'projectsPage').details.actions.client.captureActive = true
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    var projects = []
    for (var i = 1; i <= 30; i++)
      projects.push({
        id: 'p-' + i,
        name: 'Project ' + i + ' with a readable full repository name',
        tools: {},
        workspaceMode: 'dedicated',
        lastCheckoutId: 'c-' + i,
        checkouts: [
          {
            id: 'c-' + i,
            path: '/work/development/project-' + i,
            branch: 'main'
          }
        ]
      })
    entry.projectController.state = {
      roots: [],
      ignored: [],
      projects: projects
    }
    surface.navigate('p-1')
    surface.chooseSection('help')
    t.step(250, function () {
      var sidebar = t.findChild(surface, 'projectsSidebar'), list = t.findChild(sidebar, 'projectsList'), row = t.findChild(sidebar, 'selectProject:p-1')
      t.check(list.contentHeight > list.height, 'large registries create a scrollable sidebar')
      t.equal(row.width, list.contentWidth, 'project rows fill their complete click target after layout settles')
      var labels = t.findChildren(row, 'projectRowName')
      t.check(labels.length === 1 && !labels[0].truncated, 'long repository names remain readable without truncation')
      input.mouseWheel(list, list.width / 2, list.height / 2, 0, -120)
      t.step(100, function () {
        t.check(list.contentY > 0, 'mouse wheel scrolls the project list')
        list.contentY = 0
        var bar = t.findChild(sidebar, 'projectsListScrollBar')
        t.check(!!bar && bar.visible && bar.interactive, 'overflowing sidebar exposes a draggable scrollbar')
        if (bar) {
          var barPos = bar.mapToItem(list, 0, 0)
          t.check(barPos.x >= 0 && barPos.x + bar.width <= list.width + 1, 'sidebar scrollbar stays inside the visible viewport')
          input.mousePress(bar, bar.width / 2, Math.max(2, bar.size * bar.height / 2))
          input.mouseMove(bar, bar.width / 2, bar.height - 2, 30, Qt.LeftButton)
          input.wait(60)
          input.mouseRelease(bar, bar.width / 2, bar.height - 2)
          input.wait(60)
          t.check(list.contentY > list.height, 'dragging the sidebar scrollbar reaches projects below the first page')
        }
        list.contentY = 0
        row.forceActiveFocus()
        input.keyClick(Qt.Key_PageDown)
        t.step(100, function () {
          t.check(list.contentY > 0, 'PageDown scrolls the focused project list')
          var last = t.findChild(sidebar, 'selectProject:p-30')
          last.forceActiveFocus()
          t.step(100, function () {
            var pos = last.mapToItem(list.contentItem, 0, 0)
            t.check(pos.y >= list.contentY - 1 && pos.y + last.height <= list.contentY + list.height + 1, 'keyboard focus reveals the complete last project row')
            var content = t.findChild(surface, 'projectsContentViewport')
            t.check(!!content && content.contentHeight > content.height, 'Help content has a scrollable production viewport')
            if (content) {
              content.contentY = 0
              input.mouseWheel(content, content.width / 2, content.height / 2, 0, -120)
              t.step(100, function () {
                t.check(content.contentY > 0, 'mouse wheel scrolls the project content pane')
                content.contentY = 0
                var mainBar = t.findChild(surface, 'settingsScrollBar')
                var mainPos = mainBar.mapToItem(content, 0, 0)
                t.check(mainPos.x >= 0 && mainPos.x + mainBar.width <= content.width + 1, 'content scrollbar stays inside the visible viewport')
                input.mousePress(mainBar, mainBar.width / 2, Math.max(2, mainBar.size * mainBar.height / 2))
                input.mouseMove(mainBar, mainBar.width / 2, mainBar.height - 2, 30, Qt.LeftButton)
                input.wait(60)
                input.mouseRelease(mainBar, mainBar.width / 2, mainBar.height - 2)
                input.wait(60)
                t.check(content.contentY >= content.contentHeight - content.height - 1, 'dragging the content scrollbar reaches the final help section')
                Style.fontBaseSize = Math.round(Style.fontBaseSize * 1.5)
                var fonts = Object.assign({}, Style.fontOverrides)
                Object.keys(fonts).forEach(function (key) {
                  fonts[key] = Math.round(Number(fonts[key]) * 1.5)
                })
                Style.fontOverrides = fonts
                window.implicitWidth = 652
                window.implicitHeight = 452
                surface.chooseSection('preferences')
                t.step(150, function () {
                  var remove = t.findChildren(surface, 'pill').filter(function (button) {
                    return button.text === 'Remove registration'
                  })[0]
                  t.check(!!remove, 'large-font Preferences retains its final registration control')
                  if (remove) {
                    remove.forceActiveFocus()
                    t.step(80, function () {
                      var y = remove.mapToItem(content.contentItem, 0, 0).y
                      t.check(y >= content.contentY - 1 && y + remove.height <= content.contentY + content.height + 1, 'keyboard focus fully reveals the bottom control on a short large-font screen')
                      t.done()
                    })
                  } else
                    t.done()
                })
              })
            } else
              t.done()
          })
        })
      })
    })
  }
}
