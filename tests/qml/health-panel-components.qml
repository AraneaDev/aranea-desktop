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

  Component.onCompleted: {
    t.equal(problems.problems.length, 1, "health problem sections expose rows")
    t.equal(processes.cpuProcesses.length, 1, "health process sections expose CPU rows")
    t.equal(processes.memoryProcesses.length, 1, "health process sections expose memory rows")
    t.equal(resources.cpu, 42, "health resource sections expose CPU state")
    t.equal(resources.diskRows.length, 1, "health resource sections expose disk rows")
    t.equal(resources.active, true, "health resource sections expose active state")
    t.equal(resources.metrics.cpu, undefined, "health resource sections expose metrics state")
    t.check(hasText(processesMemory, MetricsLogic.humanBytes(1048576)), "health process sections render the memory column's value")
    t.done()
  }
}
