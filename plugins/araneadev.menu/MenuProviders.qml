// Bash providers of the Aranea menu (MenuProviders): submenus such as Fonts
// and Power Profile fill on demand from a one-line enumeration that prints
// `label\tvalue\tcurrent` per row. One process runs at a time; later menus
// queue. The Apps provider is QML-native and handed back through
// appsRequested. Menu.qml owns one and merges rowsReady into its items.
import Quickshell.Io
import QtQuick
import qs.Commons
import "MenuModel.js" as MenuModel

Item {
  id: providers

  // All menu items by id (from the menu).
  property var items: ({})
  // Item ids in declaration order (from the menu).
  property var itemOrder: []
  // Submenu ids whose provider has run (or started) since the last reset.
  property var loaded: ({})
  // Submenu ids waiting for providerProc to become free.
  property var queue: []
  // Bumped on each reset so output from an older run is discarded.
  property int revision: 0
  // Menu ids whose bash provider is running (id -> true).
  property var loadingMenus: ({})
  // Menu ids whose last bash provider run exited nonzero (id -> true).
  property var errorMenus: ({})
  // Each known provider is a tiny bash one-liner that enumerates a list and
  // emits one tab-delimited row per item: `label\tvalue\tcurrent`. The shell
  // turns those into menu items children of `menuId`. A `volatile` provider
  // re-runs every time its submenu is entered, so a font installed since the
  // shell started shows up without restarting it. Not readonly: tests swap
  // in fake providers.
  property var specs: ({
      "fonts": {
        script: "current=$(omarchy-font-current 2>/dev/null); omarchy-font-list 2>/dev/null | while read -r f; do [[ -z $f ]] && continue; printf '%s\\t%s\\t%s\\n' \"$f\" \"$f\" \"$current\"; done",
        icon: "\ue659",
        volatile: true,
        actionFor: function (value) {
          return "omarchy-font-set " + Util.shellQuote(value)
        }
      },
      "power-profiles": {
        script: "current=$(powerprofilesctl get 2>/dev/null); omarchy-powerprofiles-list 2>/dev/null | while read -r p; do [[ -z $p ]] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
        icon: "\udb81\udc0b",
        actionFor: function (value) {
          return "omarchy-powerprofiles-set autodetect " + Util.shellQuote(value)
        }
      }
    })

  // Emitted with a provider's rows for MENUID, ready to swap in.
  signal rowsReady(string menuId, var rows)
  // Emitted when the Apps submenu needs its QML-native rows.
  signal appsRequested

  // Returns the item with this id, or null.
  function entry(id: string): var {
    return providers.items[id] || null
  }

  // Returns a copy of map with key set (or removed); maps are replaced, not mutated, so bindings update.
  function withFlag(map: var, key: string, value: bool): var {
    var next = ({})
    for (var k in map)
      next[k] = map[k]
    if (value)
      next[key] = true
    else
      delete next[key]
    return next
  }

  // Forgets every run: nothing counts as loaded, the queue empties, and output of a running process is dropped.
  function reset(): void {
    providers.revision += 1
    providers.loaded = ({})
    providers.queue = []
    providers.loadingMenus = ({})
    providers.errorMenus = ({})
  }

  // Runs the provider of submenu `id` unless it already ran; apps merge inline, others start providerProc.
  function start(id: string): void {
    var entry = providers.entry(id)
    if (!entry || !entry.provider || providers.loaded[id])
      return
    if (entry.provider === "apps") {
      providers.loaded[id] = true
      providers.appsRequested()
      return
    }
    var spec = providers.specs[entry.provider]
    if (!spec)
      return
    providers.loaded[id] = true
    providers.loadingMenus = providers.withFlag(providers.loadingMenus, id, true)
    providers.errorMenus = providers.withFlag(providers.errorMenus, id, false)
    providerProc.menuId = id
    providerProc.providerKey = entry.provider
    providerProc.revision = providers.revision
    providerProc.collected = ""
    providerProc.command = ["bash", "-lc", spec.script]
    providerProc.running = true
  }

  // Starts the next queued provider once providerProc is free.
  function startNextProvider(): void {
    if (providerProc.running)
      return
    while (providers.queue.length > 0) {
      var id = providers.queue.shift()
      var entry = providers.entry(id)
      if (!entry || !entry.provider || providers.loaded[id])
        continue
      providers.start(id)
      return
    }
  }

  // Entering a submenu is the one moment a volatile list is worth paying for
  // again: it may have been reshaped by the last pick from it. Search doesn't
  // invalidate, or every keystroke would restart the same enumeration.
  function invalidateVolatile(id: string): void {
    var entry = providers.entry(id)
    var spec = entry && entry.provider ? providers.specs[entry.provider] : null
    if (spec && spec.volatile)
      providers.loaded[id] = false
  }

  // Loads submenu `id`'s provider, queueing it when providerProc is busy.
  function load(id: string): void {
    var entry = providers.entry(id)
    if (!entry || !entry.provider || providers.loaded[id])
      return

    // Native providers don't touch providerProc, so they never need to queue.
    if (entry.provider === "apps") {
      providers.start(id)
      return
    }

    if (providerProc.running) {
      if (providers.queue.indexOf(id) < 0)
        providers.queue = providers.queue.concat([id])
      return
    }

    providers.start(id)
  }

  // Loads every not-yet-run provider under the active menu so search can see its rows.
  function loadForSearch(activeMenu: string): void {
    var active = providers.entry(activeMenu) ? activeMenu : "root"

    for (var i = 0; i < providers.itemOrder.length; i++) {
      var entry = providers.entry(providers.itemOrder[i])
      if (!entry || !entry.provider || providers.loaded[entry.id])
        continue
      if (active !== "root" && entry.id !== active && !MenuModel.isDescendantOf(providers.items, entry.id, active))
        continue
      providers.load(entry.id)
    }
  }

  // Turns a provider's tab-separated output into action rows under `menuId`.
  function rowsFromOutput(output: string, menuId: string, providerKey: string): var {
    var spec = providers.specs[providerKey]
    if (!spec)
      return []
    var lines = String(output || "").split("\n")
    var providerRows = []
    var takenIds = ({})
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].trim()
      if (!line)
        continue
      var parts = line.split("\t")
      var label = parts[0] || ""
      var value = parts[1] || parts[0] || ""
      var current = parts[2] || ""
      if (!label)
        continue
      // Distinct values can slugify alike: Fira Code and Fira-Code both give
      // fira-code, and a repeated id is dropped, which would silently lose a
      // row from the list. Nudge it until it is the row's own.
      var rowId = menuId + "." + MenuModel.slugify(value)
      while (takenIds[rowId])
        rowId += "-"
      takenIds[rowId] = true

      providerRows.push({
        id: rowId,
        parent: menuId,
        kind: "action",
        icon: (value === current) ? "✓" : (spec.icon || ""),
        label: label,
        title: "",
        target: "",
        description: "",
        action: spec.actionFor(value),
        provider: "",
        aliases: [],
        when: "",
        checked: "",
        order: 0
      })
    }
    return providerRows
  }

  Process {
    id: providerProc
    property string menuId: ""
    property string providerKey: ""
    property string collected: ""
    property int revision: 0
    stdout: SplitParser {
      onRead: function (data) {
        providerProc.collected += data + "\n"
      }
    }
    onExited: function (exitCode, exitStatus) {
      providers.loadingMenus = providers.withFlag(providers.loadingMenus, providerProc.menuId, false)
      if (providerProc.revision === providers.revision) {
        providers.errorMenus = providers.withFlag(providers.errorMenus, providerProc.menuId, exitCode !== 0)
        if (providers.specs[providerProc.providerKey])
          providers.rowsReady(providerProc.menuId, providers.rowsFromOutput(providerProc.collected, providerProc.menuId, providerProc.providerKey))
      }
      providers.startNextProvider()
    }
  }
}
