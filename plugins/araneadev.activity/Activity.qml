// Keep-loaded IPC owner; opening or closing a panel never owns activity work.
import QtQuick
import Quickshell.Io

Item {
  id: root
  // Required menu lifecycle has no independent window.
  property bool opened: false
  // Captures disable all store, provider and desktop I/O.
  property alias captureActive: controller.captureActive
  // Narrow composition boundary for notification and panel integration.
  property alias owner: controller
  ActivityRuntime {
    id: runtime
    captureActive: controller.captureActive
  }
  ActivityController {
    id: controller
    runtime: runtime
  }
  // Refresh is read-only and independent of menu visibility.
  function open(payload: string): void {
    controller.refresh()
  }
  // Accepted work survives client closure.
  function close(): void {
    opened = false
  }
  IpcHandler {
    target: 'aranea.activity'
    function snapshot(): string {
      return JSON.stringify(controller.snapshot())
    }
    function request(json: string): string {
      return JSON.stringify(controller.requestJSON(json))
    }
    function operation(id: string): string {
      return JSON.stringify(controller.operation(id))
    }
    function dismiss(taskId: string): string {
      return JSON.stringify(controller.dismiss(taskId))
    }
    function reobserve(id: string): string {
      return JSON.stringify(controller.reobserve(id))
    }
  }
  Component.onCompleted: controller.refresh()
}
