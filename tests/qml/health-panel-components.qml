// Behaviour contracts for health panel sections.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.health" as HealthComponents
import "plugins/araneadev.health/MetricsLogic.js" as MetricsLogic

ShellRoot {
  QmlTest {
    id: t
  }

  // True when ITEM or one of its descendants is a Text with this exact text.
  function hasText(item, text) {
    if (item.text !== undefined && item.text === text)
      return true
    for (var i = 0; i < item.children.length; i++) {
      if (hasText(item.children[i], text))
        return true
    }
    return false
  }

  HealthComponents.HealthProblemsSection {
    id: problems
    problems: [
      {
        glyph: "!",
        summary: "Disk",
        urgency: 2
      }
    ]
  }

  HealthComponents.HealthProcessSection {
    id: processes
    cpuProcesses: [
      {
        comm: "shell",
        percent: 2
      }
    ]
    memoryProcesses: [
      {
        comm: "shell",
        rss: 1000
      }
    ]
  }

  HealthComponents.HealthProcessSection {
    id: processesMemory
    cpuProcesses: [
      {
        comm: "a",
        percent: 5
      }
    ]
    memoryProcesses: [
      {
        comm: "b",
        rss: 1048576
      }
    ]
  }

  HealthComponents.HealthResourceSection {
    id: resources
    metrics: ({})
    active: true
    cpu: 42
    memoryPercent: 55
    diskRows: [
      {
        target: "/",
        percent: 40,
        avail: 1000
      }
    ]
    networkLabel: "eth0"
  }

  HealthComponents.HealthSummary {
    id: unavailableSummary
    width: 360
    available: false
    status: "healthy"
  }

  HealthComponents.HealthSummary {
    id: criticalSummary
    width: 360
    available: true
    status: "critical"
    problems: [
      {
        urgency: 2
      },
      {
        urgency: 1
      }
    ]
    metrics: ({
        cpu: 0,
        mem: {
          memUsed: 0,
          memTotal: 100
        },
        diskRows: [
          {
            target: "/",
            percent: 20
          },
          {
            target: "/boot",
            percent: 80
          }
        ]
      })
  }

  HealthComponents.HealthSummary {
    id: emptySummary
    width: 360
    available: true
  }

  HealthComponents.HealthDropdown {
    id: healthView
    width: 380
  }

  HealthComponents.HealthResourceSection {
    id: unknownResources
    width: 360
  }

  HealthComponents.HealthProcessSection {
    id: emptyProcesses
    width: 360
  }

  HealthComponents.HealthProcessSection {
    id: unknownProcesses
    width: 360
    cpuProcesses: [
      {
        comm: "unknown CPU",
        percent: null
      }
    ]
    memoryProcesses: [
      {
        comm: "unknown memory",
        rss: null
      }
    ]
  }

  // Many problems and expanded sections share the same capped viewport.
  HealthComponents.HealthDropdown {
    id: cappedView
    width: 380
    maxContentHeight: 300
    available: true
    status: "critical"
    problems: Array.from({
      length: 25
    }, function (_, i) {
      return {
        key: "problem:" + i,
        summary: "Issue " + i,
        urgency: 2
      }
    })
    resourcesExpanded: true
    processesExpanded: true
  }

  Component.onCompleted: {
    t.check(hasText(unavailableSummary, "Health data unavailable"), "an unavailable service never reads healthy")
    t.check(hasText(unavailableSummary, "—"), "unknown resources render an em dash")
    t.check(!hasText(unavailableSummary, "0%"), "unknown CPU never renders zero")
    t.check(hasText(criticalSummary, "2 issues need attention") && hasText(criticalSummary, "critical"), "critical summary keeps count and severity text")
    t.check(hasText(criticalSummary, "/boot · 80%"), "summary chooses the fullest disk with its mount")
    t.check(hasText(emptySummary, "No detected problems"), "empty available health is clearly healthy")
    t.check(!healthView.resourcesExpanded && !healthView.processesExpanded, "details begin collapsed")
    t.check(!healthView.problemsView.visible, "unavailable composition hides the old healthy fallback")
    t.equal(t.findChild(unknownResources, "cpuValue").text, "—", "unknown detail CPU is not zero")
    t.equal(t.findChild(unknownResources, "memValue").text, "—", "unknown detail memory is not zero")
    t.check(hasText(emptyProcesses, "No process data"), "empty processes retain a readable empty state")
    t.check(hasText(unknownProcesses, "—"), "unknown process values render an em dash")
    t.check(!hasText(unknownProcesses, "null%") && !hasText(unknownProcesses, "0 B"), "unknown process metrics never imply measured zero")
    t.equal(problems.problems.length, 1, "health problem sections expose rows")
    t.equal(processes.cpuProcesses.length, 1, "health process sections expose CPU rows")
    t.equal(processes.memoryProcesses.length, 1, "health process sections expose memory rows")
    t.equal(resources.cpu, 42, "health resource sections expose CPU state")
    t.equal(resources.diskRows.length, 1, "health resource sections expose disk rows")
    t.equal(resources.active, true, "health resource sections expose active state")
    t.equal(resources.metrics.cpu, undefined, "health resource sections expose metrics state")
    t.check(hasText(processesMemory, MetricsLogic.humanBytes(1048576)), "health process sections render the memory column's value")
    t.step(80, function () {
      t.check(cappedView.height <= 300.5, "many problems and expanded details respect available content height")
      var hint = t.findChild(cappedView, "keyHint")
      t.check(hint.y + hint.height <= cappedView.height + 0.5, "fixed keyboard hint stays inside the capped content")
      t.check(cappedView.scrollViewport.contentHeight > cappedView.scrollViewport.height, "many problems scroll within the content budget")
      cappedView.keyboardCursor = true
      cappedView.cursorKey = "details:processes"
      t.step(50, function () {
        t.check(cappedView.scrollViewport.contentY > 0, "keyboard navigation scrolls the processes heading into view")
        cappedView.keyboardCursor = false
        cappedView.scrollViewport.contentY = 0
        cappedView.keyboardCursor = true
        t.step(50, function () {
          t.check(cappedView.scrollViewport.contentY > 0, "first-key reveal scrolls an unchanged cursor key back into view")
          t.done()
        })
      })
    })
  }
}
