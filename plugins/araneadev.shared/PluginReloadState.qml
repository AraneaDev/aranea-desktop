// Shared activity flags only; authentication objects and credentials stay private.
pragma Singleton
import QtQuick

QtObject {
  id: state
  // Every active guard has its own key, so one instance cannot clear another.
  property var locks: ({})
  // Activity flags for each live authentication prompt owner.
  property var prompts: ({})
  // Missing authentication owners keep reloads deferred during startup/handover.
  readonly property bool blocked: !allIdle(locks) || !allIdle(prompts)

  // Requires at least one owner and an idle report from every owner.
  function allIdle(owners: var): bool {
    var keys = Object.keys(owners)
    return keys.length > 0 && keys.every(function (key) {
      return owners[key] === false
    })
  }

  // Publishes a copied map so dependent QML bindings reevaluate.
  function update(kind: string, key: string, busy: bool): void {
    var owners = Object.assign({}, kind === 'lock' ? locks : prompts)
    owners[key] = busy
    if (kind === 'lock')
      locks = owners
    else if (kind === 'polkit')
      prompts = owners
  }

  // Removes only the departing owner during service handover.
  function remove(kind: string, key: string): void {
    var owners = Object.assign({}, kind === 'lock' ? locks : prompts)
    delete owners[key]
    if (kind === 'lock')
      locks = owners
    else if (kind === 'polkit')
      prompts = owners
  }
}
