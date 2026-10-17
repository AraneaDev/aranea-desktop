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
    // First page; read the rest with snapshotPage(taskPage.token, offset).
    function snapshot(): string {
      return JSON.stringify(controller.ipcSnapshot())
    }
    function snapshotPage(token: string, offset: int): string {
      return JSON.stringify(controller.ipcSnapshotPage(token, offset))
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
    // JSON array of task IDs, removed in one store write.
    function dismissMany(json: string): string {
      var ids = null
      try {
        ids = JSON.parse(json)
      } catch (e) {}
      return JSON.stringify(controller.dismissMany(ids))
    }
    function reobserve(id: string): string {
      return JSON.stringify(controller.reobserve(id))
    }
  }
  Component.onCompleted: controller.refresh()
}
