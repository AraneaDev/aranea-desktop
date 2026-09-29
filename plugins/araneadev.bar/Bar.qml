// Aranea bar: the araneadev.bar plugin's `bar` entry point (manifest.json),
// loaded by the omarchy-shell host in place of the stock omarchy.bar. Builds
// one bar surface per monitor from the host's barConfig (showing exactly the
// configured layout), and handles popouts, tooltips, drag-reorder and bar moves.
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "BarModel.js" as BarModel

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: fallbackBarWidgetRegistry
  // Read-only registry view for third-party full bars; the built-in bar does
  // not otherwise need it, but declaring it keeps clone construction atomic.
  property var pluginRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding; it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  QtObject {
    id: fallbackBarWidgetRegistry
    property var widgets: ({})
    property int revision: 0
    function metadataFor(id) {
      return null
    }
  }
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  // User home directory, from $HOME.
  property string home: Quickshell.env("HOME")
  // XDG-style state directory under home (~/.local/state).
  property string stateHome: home + "/.local/state"
  // Omarchy config directory (~/.config/omarchy); custom QML modules live in its bar/modules/.
  property string omarchyConfigDir: home + "/.config/omarchy"
  // Config used when barConfig is not an object: top, transparent, clock as center anchor, empty layout.
  property var fallbackBarConfig: ({
      position: "top",
      transparent: true,
      centerAnchor: "omarchy.clock",
      layout: {
        left: [],
        center: [],
        right: []
      }
    })
  // Normalized, tray-pinned layout ({left, center, right}) the module lists are built from.
  property var layoutConfig: fallbackBarConfig.layout
  // Canonical id of the center module the center section is anchored on ("" for none).
  property string centerAnchor: ""
  // Whether transparency was requested; the surface follows it, the foreground refines it.
  property bool requestedTransparent: false
  // True once the contrast probe returned a foreground color to use over the wallpaper.
  property bool useTransparentForeground: false
  // Whether the bar surface is drawn transparent right now.
  property bool transparent: false
  // True while the pointer is over the center section.
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  // Keeps the center section's indicator peek open until the pointer leaves every bar.
  property bool centerSectionRevealHeld: false
  // Set by widgets (via their plugin API) to stop hover from revealing the center section.
  property bool centerHoverRevealSuppressed: false
  // Bumped on every structural layout change so layoutEntries re-evaluates.
  property int barConfigSerial: 0
  // Screen edge the bar sits on: top, bottom, left or right.
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  // Contrast color passed to omarchy-bar-text-color as the alternative foreground.
  property color themeContrastForeground: Color.background
  // Foreground picked by the contrast probe for the transparent bar.
  property color transparentForeground: Color.bar.text
  // Theme foreground for widgets, independent of the transparency probe.
  property color foreground: themeForeground
  // Foreground actually used on the bar: the probed color when transparent, else the theme's.
  property color barForeground: useTransparentForeground ? transparentForeground : themeForeground
  // Turned off briefly so a foreground switch jumps instead of animating.
  property bool foregroundAnimationEnabled: true
  // Whether Aranea motion is on. Starts from ARANEA_REDUCED_MOTION (1 = off);
  // once the motion state file loads, the env var wins; otherwise the file's content decides ("off" = off).
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Shared state file whose "off" content disables bar animations.
  readonly property string motionStatePath: Aranea.RuntimePaths.motionStatePath
  // Bar background color, from the Color singleton.
  property color background: Color.bar.background
  // Accent color for urgent or active states, from the Color singleton.
  property color urgent: Color.bar.active

  Behavior on barForeground {
    enabled: root.motionEnabled && root.foregroundAnimationEnabled
    ColorAnimation {
      duration: 420
      easing.type: Easing.InOutCubic
    }
  }
  Behavior on background {
    enabled: root.motionEnabled
    ColorAnimation {
      duration: 420
      easing.type: Easing.InOutCubic
    }
  }
  Behavior on urgent {
    enabled: root.motionEnabled
    ColorAnimation {
      duration: 420
      easing.type: Easing.InOutCubic
    }
  }
  // Item whose tooltip is armed or shown.
  property var tooltipTarget: null
  // Item waiting for the deferred hover check in showTooltip.
  property var pendingTooltipTarget: null
  // Text of the armed or shown tooltip.
  property string tooltipText: ""
  // Text waiting for the deferred hover check in showTooltip.
  property string pendingTooltipText: ""
  // True once the tooltip delay has passed with the target still hovered.
  property bool tooltipShown: false
  // Counter that invalidates deferred tooltip requests superseded by a newer show or hide.
  property int tooltipRequest: 0
  // The widget whose popup is open; only one at a time across the bar.
  property var activePopout: null
  // Module slot being dragged to reorder, or null.
  property var barDragSource: null
  // Slot the dragged module would drop next to, or null.
  property var barDragTarget: null
  // Screen rectangle of the drop marker ({x, y, width, height}), or null.
  property var barDragTargetGeometry: null
  // True when the drop lands after barDragTarget rather than before it.
  property bool barDragAfter: false
  // Bar window the drag started in.
  property var barDragWindow: null
  // Screen of barDragWindow; the drag ghost only shows there.
  property var barDragScreen: null
  // Grabbed image of the dragged widget, drawn as the drag ghost.
  property url barDragImageUrl: ""
  // Pointer x of the drag in bar-window scene coordinates.
  property real barDragSceneX: 0
  // Pointer y of the drag in bar-window scene coordinates.
  property real barDragSceneY: 0
  // Pointer x of the drag in screen coordinates.
  property real barDragScreenX: 0
  // Pointer y of the drag in screen coordinates.
  property real barDragScreenY: 0
  // Press x inside the dragged slot, so the ghost stays under the grab point.
  property real barDragOffsetX: 0
  // Press y inside the dragged slot, so the ghost stays under the grab point.
  property real barDragOffsetY: 0
  // True while the whole bar is being dragged to another screen edge.
  property bool barMoveActive: false
  // Edge the bar would move to if the move gesture ended now.
  property string barMoveCandidate: ""
  // Bar window the move gesture started in.
  property var barMoveWindow: null
  // Screen of barMoveWindow; the edge preview only shows there.
  property var barMoveScreen: null
  // Registered clickable widget parts, checked newest-first by moduleClickTargetAt.
  property var clickTargets: []
  // Every live module slot on every monitor's bar.
  property var moduleSlots: []
  // Plugin bar API objects keyed by plugin id, created lazily by pluginBarApiFor.
  property var pluginBarApis: ({})
  // Records {target, pluginId, clickTarget, popout} of bar objects claimed by plugins.
  property var pluginObjectOwners: []

  Component {
    id: pluginBarApiComponent
    PluginBarApi {}
  }

  // Deep copy of layoutConfig handed to plugins so they cannot mutate the live layout.
  function publicLayoutConfig(): var {
    return JSON.parse(JSON.stringify(root.layoutConfig || {}))
  }

  // Bind a plugin API object's appearance properties to the bar's, then sync its object views.
  function bindPluginBarApi(api) {
    if (!api)
      return
    api.foreground = Qt.binding(function () {
      return root.foreground
    })
    api.barForeground = Qt.binding(function () {
      return root.barForeground
    })
    api.background = Qt.binding(function () {
      return root.background
    })
    api.urgent = Qt.binding(function () {
      return root.urgent
    })
    api.fontFamily = Qt.binding(function () {
      return root.fontFamily
    })
    api.position = Qt.binding(function () {
      return root.position
    })
    api.vertical = Qt.binding(function () {
      return root.vertical
    })
    api.barSize = Qt.binding(function () {
      return root.barSize
    })
    api.transparent = Qt.binding(function () {
      return root.transparent
    })
    api.foregroundAnimationEnabled = Qt.binding(function () {
      return root.foregroundAnimationEnabled
    })
    api.centerSectionRevealHeld = Qt.binding(function () {
      return root.centerSectionRevealHeld
    })
    api._centerHoverRevealSuppressed = Qt.binding(function () {
      return root.centerHoverRevealSuppressed
    })
    root.syncPluginBarApiObjects(api)
  }

  // Refresh a plugin API's view of the popout, its own click targets and the layout; a foreign popout shows as a marker.
  function syncPluginBarApiObjects(api) {
    if (!api)
      return
    api.activePopout = root.pluginOwnsBarObject(api.pluginId, root.activePopout) ? root.activePopout : (root.activePopout ? api.foreignPopoutMarker : null)
    api.clickTargets = root.pluginClickTargets(api.pluginId)
    api.layoutConfig = root.publicLayoutConfig()
  }

  // Ownership record for a bar object, or null when no plugin claimed it.
  function pluginObjectRecord(target) {
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (record && record.target === target)
        return record
    }
    return null
  }

  // Claim target for a plugin in a role (clickTarget or popout); false when another plugin owns it.
  function markPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    if (!key || !target)
      return false
    var record = root.pluginObjectRecord(target)
    if (record && record.pluginId !== key)
      return false
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var existing = pluginObjectOwners[i]
      if (!existing || existing.target !== target)
        next.push(existing)
    }
    var updated = record || {
      target: target,
      pluginId: key,
      clickTarget: false,
      popout: false
    }
    updated[role] = true
    next.push(updated)
    pluginObjectOwners = next
    return true
  }

  // Drop a plugin's role on target, removing the record once no role is left.
  function unmarkPluginObject(pluginId, target, role) {
    var key = String(pluginId || "")
    var next = []
    for (var i = 0; i < pluginObjectOwners.length; i++) {
      var record = pluginObjectOwners[i]
      if (!record || record.target !== target || record.pluginId !== key) {
        next.push(record)
        continue
      }
      record[role] = false
      if (record.clickTarget || record.popout)
        next.push(record)
    }
    pluginObjectOwners = next
  }

  // Whether target is claimed by the given plugin.
  function pluginOwnsBarObject(pluginId, target) {
    var record = target ? root.pluginObjectRecord(target) : null
    return !!record && record.pluginId === String(pluginId || "")
  }

  // The registered click targets owned by one plugin.
  function pluginClickTargets(pluginId) {
    var out = []
    for (var i = 0; i < root.clickTargets.length; i++) {
      var target = root.clickTargets[i]
      if (root.pluginOwnsBarObject(pluginId, target))
        out.push(target)
    }
    return out
  }

  // Run syncPluginBarApiObjects on every plugin API.
  function syncAllPluginBarApiObjects(): void {
    for (var id in pluginBarApis)
      root.syncPluginBarApiObjects(pluginBarApis[id])
  }

  // Register a click target on behalf of a plugin, if it can claim it.
  function registerPluginClickTarget(pluginId, target) {
    if (!root.markPluginObject(pluginId, target, "clickTarget"))
      return
    root.registerClickTarget(target)
  }

  // Unregister a plugin's click target, only if that plugin owns it.
  function unregisterPluginClickTarget(pluginId, target) {
    if (!root.pluginOwnsBarObject(pluginId, target))
      return
    root.unregisterClickTarget(target)
    root.unmarkPluginObject(pluginId, target, "clickTarget")
  }

  // Open a popout on behalf of a plugin, if it can claim the owner.
  function requestPluginPopout(pluginId, owner) {
    if (!root.markPluginObject(pluginId, owner, "popout"))
      return
    root.requestPopout(owner)
  }

  // Release a plugin's popout, only if that plugin owns it.
  function releasePluginPopout(pluginId, owner) {
    if (!root.pluginOwnsBarObject(pluginId, owner))
      return
    root.releasePopout(owner)
    root.unmarkPluginObject(pluginId, owner, "popout")
  }

  // Get or create the bar API for a plugin id, refreshing its shell facade; null for an empty id.
  function pluginBarApiFor(pluginId, moduleName, registered) {
    var key = String(pluginId || "")
    if (!key)
      return null

    var pluginShell = null
    if (registered && root.shell && typeof root.shell.pluginShellForId === "function") {
      // Only the trusted built-in bar receives ShellRoot and can request a
      // service-capable facade for the widget it is instantiating.
      pluginShell = root.shell.pluginShellForId(moduleName)
    } else if (root.shell && typeof root.shell.pluginShellForBarEntry === "function") {
      // Replacement bars receive a service-less entry facade. Giving an
      // untrusted bar a generic facade factory would let it retrieve another
      // third-party plugin's live service object.
      pluginShell = root.shell.pluginShellForBarEntry(key, moduleName)
    }

    if (pluginBarApis[key]) {
      pluginBarApis[key].shell = pluginShell
      return pluginBarApis[key]
    }

    var api = pluginBarApiComponent.createObject(null, {
      pluginId: key,
      moduleName: String(moduleName || ""),
      shell: pluginShell,
      _showTooltip: function (target, text) {
        root.showTooltip(target, text)
      },
      _hideTooltip: function (target) {
        root.hideTooltip(target)
      },
      _registerClickTarget: function (target) {
        root.registerPluginClickTarget(key, target)
      },
      _unregisterClickTarget: function (target) {
        root.unregisterPluginClickTarget(key, target)
      },
      _requestPopout: function (owner) {
        root.requestPluginPopout(key, owner)
      },
      _releasePopout: function (owner) {
        root.releasePluginPopout(key, owner)
      },
      _switchPanelFrom: function (owner, direction) {
        return root.switchPanelFrom(owner, direction)
      },
      _targetBelongsToWindow: function (target, window) {
        return root.targetBelongsToWindow(target, window)
      },
      _moduleWidgets: function (requestedId) {
        return String(requestedId || "") === String(moduleName || "") ? root.moduleWidgets(moduleName) : []
      },
      _run: function (command) {
        root.run(command)
      },
      _setCenterHoverRevealSuppressed: function (value) {
        root.centerHoverRevealSuppressed = !!value
      }
    })
    if (!api)
      return null
    root.bindPluginBarApi(api)

    var next = ({})
    for (var id in pluginBarApis)
      next[id] = pluginBarApis[id]
    next[key] = api
    pluginBarApis = next
    return api
  }

  // Whether any module slot still uses the plugin API with this id.
  function pluginBarApiUsed(pluginId: string): bool {
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.pluginApiId === pluginId)
        return true
    }
    return false
  }

  // Unregister and forget every click target and popout a plugin owns.
  function releasePluginObjects(pluginId) {
    var owned = pluginObjectOwners.slice()
    for (var i = 0; i < owned.length; i++) {
      var record = owned[i]
      if (!record || record.pluginId !== pluginId)
        continue
      if (record.clickTarget)
        root.unregisterClickTarget(record.target)
      if (record.popout && root.activePopout === record.target)
        root.releasePopout(record.target)
    }
    pluginObjectOwners = pluginObjectOwners.filter(function (record) {
      return record && record.pluginId !== pluginId
    })
  }

  // Destroy plugin APIs no slot uses any more, releasing their objects.
  function prunePluginBarApis(): void {
    var next = ({})
    for (var id in pluginBarApis) {
      var api = pluginBarApis[id]
      if (root.pluginBarApiUsed(id)) {
        next[id] = api
        continue
      }
      root.releasePluginObjects(id)
      if (api && typeof api.destroy === "function")
        api.destroy()
    }
    pluginBarApis = next
  }

  onActivePopoutChanged: syncAllPluginBarApiObjects()
  onClickTargetsChanged: syncAllPluginBarApiObjects()
  onLayoutConfigChanged: syncAllPluginBarApiObjects()
  onModuleSlotsChanged: Qt.callLater(prunePluginBarApis)

  Component.onDestruction: {
    for (var id in pluginBarApis) {
      root.releasePluginObjects(id)
      if (pluginBarApis[id] && typeof pluginBarApis[id].destroy === "function")
        pluginBarApis[id].destroy()
    }
    pluginBarApis = ({})
  }

  // Add a clickable item to clickTargets (ignored if null or already there).
  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1)
      return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  // Remove an item from clickTargets.
  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function (item) {
      return item !== target
    })
    clickTargets = next
  }

  // Add a module slot to moduleSlots (ignored if null or already there).
  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1)
      return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  // Remove a module slot from moduleSlots.
  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function (item) {
      return item !== slot
    })
    moduleSlots = next
  }

  // Scene geometry and visibility of every live slot, for the shell's debug IPC.
  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem)
        continue
      var point = {
        x: slot.x,
        y: slot.y
      }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {}
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  // The Quickshell window an item lives in, or null.
  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  // Whether target lives in the given window.
  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  // Window of a slot, via its active item first.
  function slotWindow(slot) {
    if (!slot)
      return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  // Whether two windows are the same, or sit on the same named screen.
  function sameWindow(left, right) {
    if (!left || !right)
      return false
    if (left === right)
      return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  // Whether target is visible and reports its tooltip area hovered.
  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  // Stop the tooltip timer and clear the pending and shown tooltip.
  function clearTooltip(): void {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  // Reset all module-drag state.
  function clearBarDrag(): void {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  // Map a scene point in a bar window to screen coordinates, offsetting bottom and right bars.
  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen)
      return {
        x: x,
        y: y
      }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)

    return {
      x: x,
      y: y
    }
  }

  // windowScreenPoint for the window the current drag started in.
  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  // Screen rectangle of the thin drop marker before or after slot; null if it cannot be mapped.
  function dropMarkerRect(slot, after) {
    if (!slot)
      return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) {
      edge = "bottom"
      best = 1 - ny
    }
    if (nx < best) {
      edge = "left"
      best = nx
    }
    if (1 - nx < best) {
      edge = "right"
      best = 1 - nx
    }
    return edge
  }

  // Start the bar-move gesture from a window, with the current edge as candidate.
  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  // Update the move candidate to the screen edge nearest screenPoint.
  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen)
      return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  // Reset the bar-move gesture state.
  function clearBarMove(): void {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  // End the move gesture and move the bar if the candidate edge differs.
  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  // Persist a new bar position to shell.json, or set it locally when there is no shell.
  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function (config) {
        if (!Util.isPlainObject(config.bar))
          config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  // Grab the dragged slot's widget to an image for the drag ghost.
  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function")
      return
    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function (result) {
      if (root.barDragSource !== slot || !result || !result.url)
        return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  // Make owner the active popout, closing the previous one first.
  function requestPopout(owner) {
    if (activePopout === owner)
      return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout)
        activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout)
        activePopout.close()
    }
    activePopout = owner
  }

  // Clear the active popout if owner holds it.
  function releasePopout(owner) {
    if (activePopout === owner)
      activePopout = null
  }

  // True for a left or right bar.
  readonly property bool vertical: position === "left" || position === "right"
  // Bar thickness from Style, per orientation.
  readonly property int barSize: vertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

  // Wrapper around BarModel.normalizePosition.
  function normalizePosition(value): string {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout): var {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left: pinTrayToInner(normalized.left, "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right: pinTrayToInner(normalized.right, "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  // Apply barConfig: position, transparency, center anchor and layout (patched in place when only settings changed).
  function applyBarConfig(): void {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    // Aranea is glass by default; `bar.transparent: false` gives the opaque bar.
    setRequestedTransparency(BarModel.barTransparent(config))
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  // Write settings-only changes into layoutConfig and push the new settings to matching live widgets.
  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry))
          continue
        var item = slot.activeItem
        if (item && "settings" in item)
          item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  // The configured entries of one region, as a copy (the bar shows exactly
  // what shell.json lists); re-evaluated whenever barConfigSerial changes.
  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries.slice() : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id)
          continue
        if (window && !sameWindow(slotWindow(slot), window))
          continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0)
          continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined)
          continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  // Open the next or previous panel in owner's region on the same bar; false when there is none.
  function switchPanelFrom(owner, direction) {
    if (!owner)
      return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot)
      return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2)
      return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0)
      return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner)
      return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId: string): var {
    var id = String(pluginId || "")
    var items = []
    if (!id)
      return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id)
        continue
      items.push(slot.activeItem)
    }
    return items
  }

  // Name of the screen a slot is on, or "".
  function slotScreenName(slot): string {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName(): string {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id)
      return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem)
        continue
      if (slot.moduleName !== id)
        continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined)
        continue
      candidates.push({
        slot: slot,
        screenName: slotScreenName(slot),
        opened: item.opened === true
      })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  // Open the panel of a widget id (called by the shell's summon IPC); false if not found.
  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function")
      return false
    item.open()
    return true
  }

  // Close the panel of a widget id; false if not found.
  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function")
      return false
    item.close()
    return true
  }

  // Whether the panel of a widget id is open (used by the shell's toggle IPC).
  function isBarWidgetOpen(pluginId: string): bool {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  // Wrapper around BarModel.entrySettings.
  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  // Wrapper around BarModel.entryId.
  function entryId(entry): string {
    return BarModel.entryId(entry)
  }

  // Wrapper around BarModel.moduleString.
  function moduleString(entry, key, fallback): string {
    return BarModel.moduleString(entry, key, fallback)
  }

  // Wrapper around BarModel.entryIndex.
  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  // Wrapper around BarModel.entriesBefore.
  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  // Wrapper around BarModel.entriesAfter.
  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  // Wrapper around Util.canonicalWidgetId (maps legacy module names to plugin ids).
  function canonicalWidgetId(name): string {
    return Util.canonicalWidgetId(name)
  }

  // Expand ~/ and $HOME/ in a path against home.
  function expandPath(path: string): string {
    return BarModel.expandPath(path, home)
  }

  // Wrapper around BarModel.customModuleSafeName.
  function customModuleSafeName(name): bool {
    return BarModel.customModuleSafeName(name)
  }

  // Wrapper around BarModel.customModuleType.
  function customModuleType(entry): string {
    return BarModel.customModuleType(entry)
  }

  // file:// URL of a custom QML module's source, or "".
  function customModuleSource(entry): string {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: applyBarConfig()

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  // Count a bar surface's pointer enter or leave; schedules the peek collapse when none is hovered.
  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0)
      centerSectionRevealTimer.restart()
  }

  // Set centerHoverRevealSuppressed.
  function setCenterHoverRevealSuppressed(value) {
    centerHoverRevealSuppressed = !!value
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered)
      root.centerSectionRevealHeld = false
  }

  // Run a shell command detached; anything but a non-empty string is ignored.
  function run(command): void {
    if (typeof command !== "string" || !command.trim())
      return
    Util.execDetached(command)
  }

  // Flip bar.transparent in shell.json (or locally with no shell); called by the shell's IPC.
  function toggleTransparency(): void {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function (config) {
        if (!Util.isPlainObject(config.bar))
          config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  // The raw bar.layout[region] array of a shell.json config, creating missing levels.
  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar))
      config.bar = {}
    if (!Util.isPlainObject(config.bar.layout))
      config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region]))
      config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  // Index of the entry with id name in a raw entries array, or -1.
  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name)
        return i
    }

    return -1
  }

  // Move a module entry within a raw config before beforeName (or to the end); true if it moved.
  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0)
      return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0)
      toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex)
      return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex)
      toIndex -= 1
    if (toIndex < 0)
      toIndex = 0
    if (toIndex > toEntries.length)
      toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  // Persist moving source's module before beforeName in toRegion via shell.json; true if it moved.
  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion)
      return false
    if (source.region === toRegion && source.moduleName === beforeName)
      return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function")
      return false

    var changed = false
    root.shell.mutateShellConfig(function (config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  // Nearest drop slot and side for a scene point on the drag's bar; null outside that bar.
  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width || barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0)
        continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow))
        continue
      var slotPoint = {
        x: slot.x,
        y: slot.y
      }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {}

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  // A visible slot of module name in region on the drag's bar, excluding sourceSlot; null if none.
  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name || !slot.visible || slot.width <= 0 || slot.height <= 0)
        continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow))
        continue
      return slot
    }

    return null
  }

  // Id of the first visible module after afterName in region, or "".
  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot))
        return name
    }

    return ""
  }

  // Drop the dragged slot before, or after, targetSlot; true if the layout changed.
  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot)
      return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  // Whether target is visible, interactive and has a triggerPress method.
  function moduleTargetClickable(target) {
    return target && target.visible !== false && target.opacity !== 0 && target.interactive !== false && target.pressable !== false && target.concealed !== true && typeof target.triggerPress === "function"
  }

  // Topmost click target under a point in slot, else the slot's widget if clickable; null if none.
  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target))
        continue
      var targetPoint = {
        x: localX,
        y: localY
      }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width && targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem))
      return slot.activeItem
    return null
  }

  // Trigger a press on the click target under a point in slot; false if there is none.
  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target)
      return false

    target.triggerPress(button)
    return true
  }

  // Format a color (or color string) as #rrggbb.
  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string")
      c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  // Request a transparent or opaque bar; transparent applies at once, then the contrast probe refines the foreground.
  function setRequestedTransparency(value: bool): void {
    var nextTransparent = value
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    // The surface must become transparent immediately.  The contrast-color
    // probe is asynchronous and should only refine the foreground color; it
    // must not leave an opaque bar behind while it runs or if it is delayed.
    transparent = true
    scheduleTransparentForegroundRefresh()
  }

  // Re-enable foreground animation two event-loop turns later, after the color jump has settled.
  function restoreForegroundAnimation(): void {
    Qt.callLater(function () {
      Qt.callLater(function () {
        root.foregroundAnimationEnabled = true
      })
    })
  }

  // Restart the debounce for the contrast probe, or reset the foreground when not transparent.
  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  // Run omarchy-bar-text-color to pick a readable foreground over the wallpaper behind the bar.
  function refreshTransparentForeground(): void {
    if (!requestedTransparent || transparentForegroundProc.running)
      return
    transparentForegroundProc.command = ["omarchy-bar-text-color", root.position, String(root.barSize), colorHex(root.themeForeground), colorHex(root.themeContrastForeground)]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  onPositionChanged: scheduleTransparentForegroundRefresh()
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function (line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value))
          return
        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: Aranea.RuntimePaths.omarchyStateRoot + "/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  // Start a Process unless it is already running.
  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  // Arm a tooltip for target: checked after a deferred call, shown after tooltipTimer if still hovered.
  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function () {
      if (request !== tooltipRequest)
        return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  // Hide the tooltip if it belongs to target, cancelling pending requests.
  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target)
      return
    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget))
        root.tooltipShown = true
      else
        root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget))
      root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser {
      onRead: function (line) {
        root.barHidden = String(line).trim() === "yes"
      }
    }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // The active bar deliberately does not register the stock `omarchy.bar` IPC
  // target: the shell instantiates the built-in bar while loading config, so
  // registering the same target here creates a duplicate-handler warning.
  // FileView remains the source of truth for the toggle and avoids that race.

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Auto

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : 0
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : 0
      right: root.barHidden && root.position === "right" ? -root.barSize : 0
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0
    implicitHeight: root.vertical ? 0 : root.barSize
    // This theme's bar is a glass layer. Keep the layer itself transparent;
    // the widget groups provide their own surfaces when requested.
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

    Rectangle {
      visible: false
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      anchors.bottom: parent.bottom
      height: 1
      color: Color.accent
      opacity: 0.22
    }

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: root.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered)
          root.setBarHovered(false)
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
      color: "transparent"
      implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
      implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

      // No id inside the grouped property (qmllint rejects it); the anchor is
      // reached through its window instead.
      anchor {
        window: barWindow
        adjustment: PopupAdjustment.Slide
        edges: Edges.Top | Edges.Left
        gravity: Edges.Bottom | Edges.Right
        rect.width: 1
        rect.height: 1

        onAnchoring: {
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow))
            return
          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
            localX = -popupWidth - 6
            localY = target.height / 2 - popupHeight / 2
          }

          var point = barWindow.contentItem.mapFromItem(target, localX, localY)
          tooltipWindow.anchor.rect.x = Math.round(point.x)
          tooltipWindow.anchor.rect.y = Math.round(point.y)
        }
      }

      TooltipBubble {
        id: tooltipBubble
        text: root.tooltipText
        fontFamily: root.fontFamily
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

        // Declared first so the side modules sit above it: gestures and the
        // center hover work on all empty bar space, as in the stock bar.
        CenterModules {
          anchors.fill: parent
        }

        LeftModules {
          id: leftModules
          anchors.left: parent.left
          anchors.leftMargin: Style.space(15)
          anchors.verticalCenter: parent.verticalCenter
        }

        RightModules {
          id: rightModules
          anchors.right: parent.right
          anchors.rightMargin: Style.space(15)
          anchors.verticalCenter: parent.verticalCenter
        }
      }
    }

    Component {
      id: verticalBar

      Item {
        anchors.fill: parent

        CenterModules {
          anchors.fill: parent
        }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component {
    id: emptyModuleComponent
    Item {
      implicitWidth: 0
      implicitHeight: 0
      visible: false
    }
  }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen || (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    // qmllint disable unqualified
    BarDragOverlay {
      readonly property var targetRect: root.barDragTargetGeometry

      anchors.fill: parent
      active: ghostWindow.active && targetRect !== null
      barPosition: root.position
      targetX: targetRect ? Math.round(targetRect.x) : 0
      targetY: targetRect ? Math.round(targetRect.y) : 0
      targetWidth: targetRect ? targetRect.width : 0
      targetHeight: targetRect ? targetRect.height : 0
      dropAfter: root.barDragAfter
      accent: Color.accent
    }
    // qmllint enable unqualified
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen || (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
          }
        }
      }
    }
  }

  // The center-region entry matching centerAnchor, or null.
  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea {
          anchors.fill: parent
        }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea {
          anchors.fill: parent
        }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: verticalCenterAnchorModule.top
          anchors.horizontalCenter: verticalCenterAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: verticalCenterAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: verticalCenterAnchorModule.bottom
          anchors.horizontalCenter: verticalCenterAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      if (dragging)
        return
      dragging = true
      root.beginBarMove(root.targetWindow(gestureArea))
      var scenePoint = gestureArea.mapToItem(null, x, y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onPressed: function (mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function (mouse) {
      // A widget above us propagates its composed press-and-hold down here without
      // ever handing over the grab, so we'd get no release or cancel to end the move.
      if (!gestureArea.pressed)
        return
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function (mouse) {
      if (!(mouse.buttons & Qt.LeftButton))
        return
      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold)
          return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function (mouse) {
      if (!dragging)
        return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function (mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function (mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    readonly property var registryMetadata: root.barWidgetRegistry.metadataFor(root.canonicalWidgetId(moduleName))
    readonly property bool firstParty: registryMetadata && registryMetadata.firstParty === true
    readonly property string pluginApiId: registered ? root.canonicalWidgetId(moduleName) : "bar-entry:" + moduleName
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType)
        return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered)
        return registryLoader.item
      if (qmlCustom)
        return qmlLoader.item
      return componentLoader.item
    }
    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0)
        return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot)
        root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    HoverHandler {
      id: moduleHover
    }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical ? (root.position === "left" ? parent.width - width - inset : inset) : Math.round((parent.width - width) / 2)
      y: root.vertical ? Math.round((parent.height - height) / 2) : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation {
          duration: 120
          easing.type: Easing.OutCubic
        }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      cursorShape: root.moduleClickTargetAt(slot, mouseX, mouseY) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function (mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function (mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton))
          return
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function (mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging)
          suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function (mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y))
          mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    function injectProps() {
      var target = activeItem
      if (!target)
        return
      if ("bar" in target)
        target.bar = firstParty ? root : root.pluginBarApiFor(pluginApiId, moduleName, registered)
      if ("moduleName" in target)
        target.moduleName = moduleName
      if ("settings" in target)
        target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule {
        entry: slot.entry
      }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function (button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command)
        root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
