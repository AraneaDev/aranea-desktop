// Keep-loaded owner and independent Projects window composition root.
import QtQuick
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
  Component.onCompleted: controller.refresh()
}
