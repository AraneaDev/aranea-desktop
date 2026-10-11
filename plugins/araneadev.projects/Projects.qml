// Keep-loaded owner and independent Projects window composition root.
import QtQuick
import Quickshell
import "../araneadev.agents" as Agents
import Quickshell.Io

Item {
  id: root
  // Host menu kind requires these lifecycle hooks without presentation ownership.
  property alias opened: presentation.opened
  // Scoped plugin-host shell handle; presentation never owns the host.
  property var shell: null
  // Installed plugin manifest supplied by the host.
  property var manifest: null
  // Offscreen tests may suppress creation of the native window.
  property alias windowEnabled: presentation.windowEnabled
  // Display-only captures disable every owner/runtime boundary.
  property alias captureActive: controller.captureActive
  // Public owner boundary available to narrow composition consumers.
  property alias owner: controller
  // Shared Agents records are watched read-only; Projects never fetches usage.
  readonly property string usageDir: (Quickshell.env('XDG_STATE_HOME') || Quickshell.env('HOME') + '/.local/state') + '/omarchy/agents/usage'
  // Publish only fields used by provider suggestions.
  function syncUsage(): void {
    var trim = function (record) {
      return record ? {
        limits: Array.isArray(record.limits) ? record.limits : [],
        updatedAt: record.updatedAt || null
      } : null
    }
    controller.agentUsage = {
      claude: trim(claudeUsage.record),
      codex: trim(codexUsage.record)
    }
  }
  Agents.Agent {
    id: claudeUsage
    agentId: 'claude'
    path: root.usageDir + '/claude.json'
    onRecordChanged: root.syncUsage()
  }
  Agents.Agent {
    id: codexUsage
    agentId: 'codex'
    path: root.usageDir + '/codex.json'
    onRecordChanged: root.syncUsage()
  }
  ProjectRuntime {
    id: runtime
    captureActive: controller.captureActive
  }
  ProjectsController {
    id: controller
    runtime: runtime
  }
  ProjectsPresentation {
    id: presentation
    captureActive: root.captureActive
    shell: root.shell
    manifest: root.manifest
  }
  // Menu lifecycle does not control accepted operations or helper lifetime.
  function open(payload: string): string {
    var result = presentation.open(payload)
    if (result === 'ok')
      controller.refresh()
    return result
  }
  // Closing presentation never cancels accepted work.
  function close(): void {
    presentation.close()
  }
  IpcHandler {
    target: 'aranea.projects'
    function snapshot(): string {
      return JSON.stringify(controller.snapshot())
    }
    function request(payloadJson: string): string {
      var payload = null
      try {
        payload = JSON.parse(payloadJson)
      } catch (e) {}
      return JSON.stringify(controller.request(payload))
    }
    function prepareWorkspace(payloadJson: string): string {
      var payload = null
      try {
        payload = JSON.parse(payloadJson)
      } catch (e) {}
      return JSON.stringify(controller.prepareWorkspaceRequest(payload))
    }
    function operation(id: string): string {
      return JSON.stringify(controller.operation(id))
    }
  }
  Component.onCompleted: {
    syncUsage()
    controller.refresh()
  }
}
