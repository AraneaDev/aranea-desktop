// Behaviour contracts for health panel sections.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.health" as HealthComponents

ShellRoot {
  QmlTest { id: t }

  HealthComponents.HealthProblemsSection {
    id: problems
    problems: [{ glyph: "!", summary: "Disk", urgency: 2 }]
  }

  HealthComponents.HealthProcessSection {
    id: processes
    cpuProcesses: [{ comm: "shell", percent: 2 }]
    memoryProcesses: [{ comm: "shell", rss: 1000 }]
  }

  HealthComponents.HealthResourceSection {
    id: resources
    cpu: 42
    memoryPercent: 55
    diskRows: [{ target: "/", percent: 40, avail: 1000 }]
    networkLabel: "eth0"
  }

  Component.onCompleted: {
    t.equal(problems.problems.length, 1, "health problem sections expose rows")
    t.equal(processes.cpuProcesses.length, 1, "health process sections expose CPU rows")
    t.equal(processes.memoryProcesses.length, 1, "health process sections expose memory rows")
    t.equal(resources.cpu, 42, "health resource sections expose CPU state")
    t.equal(resources.diskRows.length, 1, "health resource sections expose disk rows")
    t.done()
  }
}
