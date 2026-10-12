// Serialize exact inactive-task dismissals through the existing activity owner.
// Injected clients use the same narrow observation interface.
// qmllint disable missing-property
import QtQuick
import "../araneadev.activity/ActivityLogic.js" as ActivityLogic

Item {
  id: queue
  // The host supplies its persistent activity observer.
  property var client: null
  // Capture and showcase modes never submit task mutations.
  property bool captureActive: false
  // Remains true between individual accepted dismissals.
  property bool pending: false
  // A failed or uncertain batch retains its explanation.
  property var error: null
  // Exact IDs frozen at the deliberate clear action.
  property var remaining: []
  // Only this task's observed completion can advance the queue.
  property string currentId: ''
  // Deferred continuations cannot cross cancellation or client changes.
  property int generation: 0
  onClientChanged: cancel()
  onCaptureActiveChanged: {
    if (captureActive)
      cancel()
  }
  // Cancel unsubmitted work; an accepted owner operation remains owned there.
  function cancel(): void {
    generation++
    remaining = []
    currentId = ''
    pending = false
  }
  // Clearing uses only distinct bounded task identities, never provider text.
  function start(ids: var): bool {
    if (captureActive || pending || !client || client.captureActive || client.pending || !Array.isArray(ids) || !ids.length || ids.length > 700 || ids.some(function (id, index) {
      return !ActivityLogic.validId(id) || ids.indexOf(id) !== index
    }))
      return false
    generation++
    error = null
    remaining = ids.slice()
    pending = true
    next()
    return true
  }
  // The store rechecks liveness for every task immediately before removal.
  function next(): void {
    if (!pending || captureActive || !client)
      return
    if (!remaining.length) {
      pending = false
      client.refresh()
      return
    }
    currentId = remaining[0]
    remaining = remaining.slice(1)
    if (!client.dismiss(currentId))
      fail(client.error || {
        code: 'CLEAR_REFUSED',
        message: 'Task clearing could not start. Refresh activity and try again.'
      })
  }
  // Partial progress is retained; uncertain work is never automatically repeated.
  function fail(reason: var): void {
    cancel()
    error = reason
    if (!captureActive && client && client.available !== false)
      client.refresh()
  }
  Connections {
    target: queue.client
    ignoreUnknownSignals: true
    function onErrorChanged() {
      if (queue.pending && queue.client.error)
        queue.fail(queue.client.error)
    }
    function onPendingChanged() {
      if (!queue.pending || queue.client.pending)
        return
      var token = queue.generation, taskId = queue.currentId
      Qt.callLater(function () {
        if (queue.pending && token === queue.generation && taskId === queue.currentId && !queue.client.pending)
          queue.fail(queue.client.error || {
            code: 'CLEAR_UNCONFIRMED',
            message: 'Task clearing was not confirmed. Refresh activity before trying again.'
          })
      })
    }
    function onOperationChanged(op) {
      if (!queue.pending || op.action !== 'dismiss' || op.taskId !== queue.currentId || op.id !== queue.client.operationId || op.ownerId !== queue.client.ownerId || op.state !== 'completed')
        return
      if (op.outcome !== 'observed') {
        queue.fail(op.error || {
          code: 'CLEAR_UNCONFIRMED',
          message: 'Task clearing was not confirmed. Refresh activity before trying again.'
        })
        return
      }
      queue.currentId = ''
      var token = queue.generation
      Qt.callLater(function () {
        if (queue.pending && token === queue.generation)
          queue.next()
      })
    }
  }
}
