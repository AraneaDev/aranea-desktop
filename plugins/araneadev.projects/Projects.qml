// Keep-loaded IPC composition root; it creates no independent window.
import QtQuick
import Quickshell.Io

Item {
  id: root
  // Host menu kind requires these lifecycle hooks without presentation ownership.
  property bool opened: false
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
  // Menu lifecycle does not control accepted operations or helper lifetime.
  function open(payload: string): void {
    controller.refresh()
  }
  // Closing presentation never cancels accepted work.
  function close(): void {
    opened = false
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
    function operation(id: string): string {
      return JSON.stringify(controller.operation(id))
    }
  }
  Component.onCompleted: controller.refresh()
}
