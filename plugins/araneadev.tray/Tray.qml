// Aranea Tray (araneadev.tray, cloned from omarchy.tray): the bar's system
// tray widget, with its app-menu and manage popups. Stock's root logic stays
// (the buckets, the drawer animation, both bar orientations, icon clicks
// and the wheel, QsMenuOpener with the submenu stack, resetTrayMenu and the
// pin/hide persistence). Changed here: the collapsed drawer reserves no
// space, so the widget needs no containment mask, and a left-click on its
// arrow holds it open; both popups are Aranea.KeyboardPanelFrame windows
// (layer-shell, focused when they map) drawing the pure TrayMenuView and
// TrayManageView; the app menu and the manage panel take the keyboard;
// every action is keyed and refused on a mismatch; pin and hide show their
// new state at once; a menu whose item leaves the tray closes; and the IPC
// target araneadev.tray opens either popup. The rules live in TrayLogic.js,
// tested under Node.
pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import Quickshell.Services.SystemTray
import qs.Commons
import qs.Ui
import "TrayModel.js" as TrayModel
import "TrayLogic.js" as TrayLogic
import "../araneadev.shared/CursorLogic.js" as CursorLogic
import "../araneadev.shared" as Aranea

BarWidget {
  id: root
  moduleName: "omarchy.tray"

  // Whether the pointer is over the drawer block (its HoverHandler).
  property bool drawerHovered: false
  // Whether the open app menu belongs to a drawer icon it is anchored to, so
  // the drawer stays slid open under the menu (the popup's full-screen
  // layer takes the pointer off the bar, which would otherwise collapse the
  // drawer and slide the anchor away).
  property bool drawerHeld: false
  // Whether a left-click on the drawer arrow holds the drawer open; another
  // click on the arrow (or IPC close) lets it go. The bar takes no keyboard
  // focus and never sees clicks outside itself, so Esc and an outside click
  // cannot close it.
  property bool drawerClickedOpen: false
  // Whether the drawer was open when the manage popup opened, so it stays
  // open under the popup: the popup's layer takes the pointer off the bar,
  // and a collapsing drawer would shrink root, the popup's anchor, and slide
  // the card sideways.
  property bool manageHeld: false
  // Whether the collapsed drawer is slid open: hovered, held open by a click
  // on the arrow, held under an open app menu of one of its icons, or held
  // under the manage popup it was open for.
  readonly property bool expanded: drawerHovered || drawerClickedOpen || (trayMenuOpen && drawerHeld) || (managePopupOpen && manageHeld)
  // Whether the manage (pin/hide) popup is open.
  property bool managePopupOpen: false
  // Whether an item's app menu popup is open.
  property bool trayMenuOpen: false
  // The SystemTray item whose app menu is open, or null.
  property var activeTrayItem: null
  // The TrayItem anchor the open app menu is positioned against.
  property var activeTrayAnchor: null
  // The bar's foreground colour, or the default when not hosted by a bar.
  // qmllint disable missing-property
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // qmllint enable missing-property
  // Item ids pinned to the bar (always visible), from the entry's settings.
  readonly property var pinnedIds: settings.pinned instanceof Array ? settings.pinned : []
  // Item ids hidden from the tray entirely, from the entry's settings.
  readonly property var hiddenIds: settings.hidden instanceof Array ? settings.hidden : []
  // Tray items pinned to the bar.
  readonly property var pinnedItems: bucket("pinned")
  // Tray items in the collapsed drawer.
  readonly property var drawerItems: bucket("drawer")
  // Every tray item Omarchy does not own, pinned, drawer or hidden.
  readonly property var allItems: bucket("all")
  // Every item the tray reports, so a vanished app menu item is noticed.
  readonly property var trayItemValues: root.listOf(SystemTray.items.values)
  // How many items sit in the drawer.
  readonly property int drawerCount: drawerItems.length
  // The square size one tray icon occupies.
  // qmllint disable missing-property
  readonly property int trayItemExtent: Style.bar.iconSlot
  // qmllint enable missing-property
  // The gap between adjacent tray icons.
  readonly property int trayItemGap: 0
  // The gap between the drawer block and the pinned row.
  readonly property int trayJoinGap: 0
  // The drawer's full extent (icon count times their slot, plus gaps).
  readonly property int drawerExtent: drawerCount > 0 ? drawerCount * trayItemExtent + (drawerCount - 1) * trayItemGap : 0
  // Match Waybar's group/tray-expander drawer transition-duration.
  readonly property int animationDuration: 600
  // 0 when the drawer is collapsed, 1 when fully revealed.
  property real revealProgress: expanded ? 1 : 0
  // The drawer's currently revealed extent (drawerExtent times revealProgress).
  readonly property real revealExtent: drawerExtent * revealProgress
  // The drawer arrow (the bar's chevron) of the loaded orientation, or null.
  property Item drawerArrow: null
  // The live TrayItem delegates, so IPC can anchor a menu to an item's icon.
  property var trayItemViews: []

  // Submenu drill-down state. QsMenuEntry.display() renders a *platform* menu,
  // which Quickshell refuses unless the shell root sets `//@ pragma
  // UseQApplication` - omarchy's shell.qml does not, so every submenu click was
  // a silent no-op ("Cannot display PlatformMenuEntry as quickshell was not
  // started in QApplication mode" in the shell log) and apps whose whole UI is
  // submenus, e.g. radiotray-ng's station list, were unusable. QsMenuEntry
  // inherits QsMenuHandle, so a child entry can feed a nested QsMenuOpener and
  // render inside this popup instead of going through the platform. Each level
  // keeps its own live opener: a child entry is owned by its parent opener's
  // model, so collapsing the stack to a single opener would destroy the very
  // entry being displayed (submenu turns up empty).
  property var submenuStack: []
  // How many levels deep the app menu has drilled (0 is the root menu).
  readonly property int submenuDepth: submenuStack.length
  // The current submenu level's title, "" at the root.
  readonly property string currentTitle: submenuDepth > 0 ? submenuStack[submenuDepth - 1].title : ""
  // The current level's menu entries: the open submenu's, or the root's.
  readonly property var currentChildren: submenuDepth > 0 ? submenuStack[submenuDepth - 1].opener.children : trayMenuOpener.children

  // Changing level rebuilds the row delegates synchronously, so the next
  // row lands under a cursor that hasn't moved. Submenu clicks used to be
  // silent no-ops, which trained users to click them twice, and that second
  // click would now fire whatever entry took the spot. Ignore row clicks for
  // a beat after each level change; a deliberate follow-up click is slower.
  property bool menuLevelSettling: false

  // ---- The app menu's view.
  // The current level's QsMenuEntry objects, in order.
  readonly property var currentEntries: root.listOf(currentChildren ? currentChildren.values : null)
  // A stable serial per QsMenuEntry object (Quickshell does not expose the
  // DBus id), so a row's key survives a live property update and changes
  // when the app replaces the entry. Cleared with the menu.
  property var entrySerials: ({
      map: new Map(),
      next: 1
    })
  // The app title stock compares the root-title entry with.
  readonly property string activeTitle: root.activeTrayItem ? String(root.activeTrayItem.title || root.activeTrayItem.id || "") : ""
  // The rows the menu view draws (TrayLogic.menuRows over the current
  // level's entries, converted from QsMenuEntry).
  readonly property var menuRowList: TrayLogic.menuRows(root.currentEntries.map(function (entry) {
    return root.entryShape(entry)
  }), root.submenuDepth === 0, root.activeTitle)
  // Whether a navigation key has shown the menu cursor (or the pointer put
  // it on a row).
  property bool menuCursorActive: false
  // True while the keyboard drives the menu cursor; any pointer action
  // clears it. The view outlines the cursor only then.
  property bool menuKeyboard: false
  // The menu cursor's position in menuRowList, or -1.
  property int menuCursorIndex: -1
  // The key of the row the menu cursor was put on, or "".
  property string menuCursorKey: ""
  // The plain view object TrayMenuView draws (see its view property).
  readonly property var menuView: ({
      title: TrayLogic.displayName(root.activeTrayItem),
      crumb: TrayLogic.crumb(root.submenuStack.map(function (level) {
        return level.title
      }), TrayLogic.displayName(root.activeTrayItem)),
      depth: root.submenuDepth,
      rows: root.menuRowList,
      empty: root.menuRowList.length === 0,
      cursor: {
        active: root.menuCursorActive && root.menuKeyboard,
        index: root.menuCursorIndex
      },
      keyHint: TrayLogic.menuKeyHint()
    })

  // ---- The manage panel's view.
  // How long a pin or hide shows its new state before the settings echo
  // must have caught up; after that the actual state shows again.
  readonly property int pendingTimeoutMs: 3000
  // Pin/hide changes waiting for the settings echo, by item id:
  // {pinned, hidden, at (Date.now())}.
  property var pendingState: ({})
  // The rows the manage view draws: one per item, keyed by its id, the
  // pending state shown in place of the saved one.
  readonly property var manageRowList: root.allItems.map(function (item) {
    var id = String(item.id || "")
    var pending = root.pendingState[id]
    return {
      key: id,
      name: TrayLogic.displayName(item),
      icon: root.trayIconSource(item.icon),
      pinned: pending ? pending.pinned : root.pinnedIds.indexOf(id) !== -1,
      hidden: pending ? pending.hidden : root.hiddenIds.indexOf(id) !== -1,
      pending: !!pending
    }
  })
  // Whether a navigation key has shown the manage cursor (or the pointer
  // put it on a row).
  property bool manageCursorActive: false
  // True while the keyboard drives the manage cursor.
  property bool manageKeyboard: false
  // The manage cursor: {row (a position in manageRowList, or -1), pill (0
  // Pin, 1 Hide)}.
  property var manageCursor: ({
      row: -1,
      pill: 0
    })
  // The key (item id) of the row the manage cursor was put on, or "".
  property string manageCursorKey: ""
  // The plain view object TrayManageView draws (see its view property).
  readonly property var manageView: ({
      rows: root.manageRowList,
      empty: root.manageRowList.length === 0,
      cursor: {
        active: root.manageCursorActive && root.manageKeyboard,
        row: root.manageCursor.row,
        pill: root.manageCursor.pill
      },
      keyHint: TrayLogic.manageKeyHint()
    })

  Component {
    id: submenuOpenerComponent
    QsMenuOpener {}
  }

  Timer {
    id: menuLevelSettleTimer
    interval: 250
    onTriggered: root.menuLevelSettling = false
  }

  // Ends pending pin/hide states that timed out.
  Timer {
    interval: 250
    repeat: true
    running: Object.keys(root.pendingState).length > 0
    onTriggered: root.settlePending()
  }

  // Marks the menu as mid-transition for a beat after a level change, so a
  // trained double-click doesn't land on whatever entry took the old spot.
  function settleMenuLevel() {
    menuLevelSettling = true
    menuLevelSettleTimer.restart()
  }

  // Tears down every open submenu level and scrolls back to the top, so the
  // next open starts fresh at the root.
  function resetTrayMenu() {
    menuLevelSettling = false
    menuLevelSettleTimer.stop()
    // Flickable keeps its offset across a model swap whenever the new content
    // is still tall enough to hold it, so a menu dismissed while scrolled
    // would otherwise reopen part-way down with its first entries off screen.
    menuViewItem.resetScroll()
    // Clear the reactive stack before tearing anything down, so no binding can
    // read a partially-destroyed opener while this runs. Then destroy deepest
    // first: an inner opener's menu entry is owned by its parent's children
    // model, so destroying a parent first would invalidate an entry a still-
    // live child opener references.
    var openers = submenuStack
    submenuStack = []
    for (var i = openers.length - 1; i >= 0; i--)
      openers[i].opener.destroy()
    entrySerials = {
      map: new Map(),
      next: 1
    }
    clearMenuCursor()
  }

  // Drills one level into a menu entry's children, opening a nested
  // QsMenuOpener for it and pushing it onto the submenu stack.
  function enterSubmenu(entry, title) {
    var opener = submenuOpenerComponent.createObject(root, {
      menu: entry
    })
    if (!opener)
      return
    var stack = submenuStack.slice()
    stack.push({
      opener: opener,
      title: title
    })
    submenuStack = stack
    clearMenuCursor()
    settleMenuLevel()
  }

  // Pops one level off the submenu stack, back to its parent.
  function leaveSubmenu() {
    if (submenuStack.length === 0)
      return
    var stack = submenuStack.slice()
    var top = stack.pop()
    submenuStack = stack
    top.opener.destroy()
    clearMenuCursor()
    settleMenuLevel()
  }

  // Closes both popups.
  function close() {
    managePopupOpen = false
    trayMenuOpen = false
  }

  // A press on the drawer arrow: left toggles the drawer held open, right
  // toggles the manage popup (stock).
  function arrowPressed(button) {
    if (button === Qt.LeftButton)
      root.drawerClickedOpen = !root.drawerClickedOpen
    else if (button === Qt.RightButton)
      root.toggleManage()
  }

  // Opens or closes the manage popup (right-click on the drawer arrow),
  // closing the app menu first so one popup holds the keyboard.
  function toggleManage() {
    if (root.managePopupOpen) {
      root.managePopupOpen = false
      return
    }
    root.trayMenuOpen = false
    root.manageHeld = root.expanded
    root.managePopupOpen = true
  }

  // Opens an item's app menu anchored to it, or falls back to the platform
  // menu display() for an item that reports no DBus menu at all.
  function openTrayMenu(item, anchorItem, mouse) {
    if (!item || !item.menu) {
      if (!item || !mouse)
        return
      var point = anchorItem.QsWindow.contentItem.mapFromItem(anchorItem, mouse.x, mouse.y)
      item.display(anchorItem.QsWindow.window, point.x, point.y)
      return
    }

    // Reset before switching items: trayMenuOpener.menu binds to
    // activeTrayItem.menu, so assigning a new item invalidates the old root's
    // children immediately, before any nested opener referencing them would
    // otherwise get torn down.
    resetTrayMenu()
    // One popup holds the keyboard at a time. Closed before the menu opens,
    // so the shared popout owner is released before it is requested again.
    managePopupOpen = false
    var switching = trayMenuOpen
    activeTrayItem = item
    activeTrayAnchor = anchorItem
    drawerHeld = anchorItem !== root.drawerArrow && anchorItem !== root && classifyItem(item) === "drawer"
    trayMenuOpen = true
    // Switching items while open changes no open state: start afresh here.
    if (switching)
      freshMenuCursor()
  }

  // The live TrayItem delegate showing ITEM, or null.
  function trayItemViewFor(item) {
    for (var i = 0; i < root.trayItemViews.length; i++) {
      var view = root.trayItemViews[i]
      if (view && view.modelData === item)
        return view
    }
    return null
  }

  // IPC `menu <index>`: opens the app menu of the pinned item at INDEX, or
  // of the drawer item past the pinned ones (TrayLogic.menuTarget),
  // anchored to its icon. A drawer item's menu holds the drawer open
  // (drawerHeld), so a collapsed drawer slides open and the menu follows
  // its icon. Out of range, or an item without a DBus menu: a no-op.
  function openMenuAt(index) {
    var target = TrayLogic.menuTarget(root.pinnedItems.length, root.drawerItems.length, index)
    if (!target)
      return
    var item = target.bucket === "pinned" ? root.pinnedItems[target.index] : root.drawerItems[target.index]
    if (!item || !item.menu)
      return
    root.openTrayMenu(item, root.trayItemViewFor(item) || root, null)
  }

  // IPC `manage`: opens the manage popup.
  function openManage() {
    root.trayMenuOpen = false
    root.manageHeld = root.expanded
    root.managePopupOpen = true
  }

  // The ready-to-use image:// URL for a tray icon.
  function trayIconSource(icon) {
    // Quickshell already resolves the tray icon into a ready-to-use image://
    // URL, including a "?path=" fallback search dir for apps that ship their
    // tray icon outside a standard theme (e.g. Steam's flat public/ dir). Hand
    // it straight to IconImage; guessing a theme sub-directory here only broke
    // apps whose layout didn't match the guess.
    return String(icon || "")
  }

  // Symbolic icons ship a fixed fill (often near-white) that the host is meant
  // to recolor to its foreground; detect them by the freedesktop "-symbolic"
  // name suffix so they can be tinted instead of rendered as-is.
  function iconIsSymbolic(icon) {
    var name = String(icon || "").split("?")[0]
    return name.slice(-9) === "-symbolic"
  }

  // The hover tooltip text for a tray item, following stock's title ->
  // tooltipTitle -> id fallback.
  function trayTooltip(item) {
    return item.tooltipTitle || item.title || item.id || ""
  }

  // Which bucket an item belongs to: hidden, pinned, or drawer.
  function classifyItem(item) {
    var iid = String(item.id || "")
    if (hiddenIds.indexOf(iid) !== -1)
      return "hidden"
    if (pinnedIds.indexOf(iid) !== -1)
      return "pinned"
    return "drawer"
  }

  // Whether a tray item is owned by Omarchy itself (TrayModel.ownedByOmarchy).
  function ownedByOmarchy(item) {
    // qmllint disable missing-property
    var layout = root.bar && root.bar.layoutConfig ? root.bar.layoutConfig : null
    // qmllint enable missing-property
    return TrayModel.ownedByOmarchy(item, layout)
  }

  // The tray items for one category ("pinned", "drawer" or "all"), skipping
  // passive items and anything Omarchy owns.
  function bucket(category) {
    var values = SystemTray.items.values
    var result = []
    for (var i = 0; i < values.length; i++) {
      var item = values[i]
      if (item.status === Status.Passive)
        continue
      if (ownedByOmarchy(item))
        continue
      if (category === "all") {
        result.push(item)
        continue
      }
      if (classifyItem(item) === category)
        result.push(item)
    }
    return result
  }

  // Saves the pinned/hidden id lists under the bar entry id (root.moduleName,
  // which Bar.qml overwrites with the entry's own id), never a literal id.
  function persistTrayState(pinned, hidden) {
    // qmllint disable missing-property
    if (!root.bar || !root.bar.shell || typeof root.bar.shell.updateEntryInline !== "function")
      return
    var id = root.moduleName || "omarchy.tray"
    root.bar.shell.updateEntryInline(id, {
      id: id,
      pinned: pinned,
      hidden: hidden
    })
    // qmllint enable missing-property
  }

  // The pinned and hidden lists as shown: the saved ones with every pending
  // change applied, so a second toggle before the echo builds on the first.
  function shownLists() {
    var pinned = root.pinnedIds.slice()
    var hidden = root.hiddenIds.slice()
    for (var id in root.pendingState) {
      var p = root.pendingState[id]
      pinned = pinned.filter(function (x) {
        return x !== id
      })
      hidden = hidden.filter(function (x) {
        return x !== id
      })
      if (p.pinned)
        pinned.push(id)
      if (p.hidden)
        hidden.push(id)
    }
    return {
      pinned: pinned,
      hidden: hidden
    }
  }

  // Shows IID's new state from LISTS at once, until the settings echo
  // matches it or pendingTimeoutMs passes.
  function markPending(iid, lists) {
    var next = Object.assign({}, root.pendingState)
    next[iid] = {
      pinned: lists.pinned.indexOf(iid) !== -1,
      hidden: lists.hidden.indexOf(iid) !== -1,
      at: Date.now(),
      sawChange: false
    }
    root.pendingState = next
  }

  // The saved pinned or hidden list changed: every pending state marked
  // before now has seen a real settings write, so a match may end it.
  function noteSettingsChange() {
    var ids = Object.keys(root.pendingState)
    var now = Date.now()
    var next = {}
    var changed = false
    for (var i = 0; i < ids.length; i++) {
      var p = root.pendingState[ids[i]]
      if (!p.sawChange && now >= p.at) {
        p = Object.assign({}, p, {
          sawChange: true
        })
        changed = true
      }
      next[ids[i]] = p
    }
    if (changed)
      root.pendingState = next
    root.settlePending()
  }

  // Drops pending states a real settings echo (one seen after the change)
  // now matches, that timed out, or whose item left the tray.
  function settlePending() {
    var ids = Object.keys(root.pendingState)
    if (ids.length === 0)
      return
    var present = root.allItems.map(function (item) {
      return String(item.id || "")
    })
    var now = Date.now()
    var next = {}
    var changed = false
    for (var i = 0; i < ids.length; i++) {
      var id = ids[i]
      var p = root.pendingState[id]
      var echoed = p.sawChange && (root.pinnedIds.indexOf(id) !== -1) === p.pinned && (root.hiddenIds.indexOf(id) !== -1) === p.hidden
      if (echoed || now - p.at >= root.pendingTimeoutMs || present.indexOf(id) === -1)
        changed = true
      else
        next[id] = p
    }
    if (changed)
      root.pendingState = next
  }

  // Pins an item (un-hiding it), or unpins it when already pinned
  // (TrayLogic.togglePin over the lists as shown).
  function togglePin(iid) {
    var shown = root.shownLists()
    var next = TrayLogic.togglePin(shown.pinned, shown.hidden, iid)
    root.markPending(iid, next)
    persistTrayState(next.pinned, next.hidden)
  }

  // Hides an item (un-pinning it), or unhides it when already hidden
  // (TrayLogic.toggleHide over the lists as shown).
  function toggleHide(iid) {
    var shown = root.shownLists()
    var next = TrayLogic.toggleHide(shown.pinned, shown.hidden, iid)
    root.markPending(iid, next)
    persistTrayState(next.pinned, next.hidden)
  }

  // Closes the app menu once its item has left the tray, and drops pending
  // states of items that vanished.
  function pruneVanished() {
    if (root.trayMenuOpen && (!root.activeTrayItem || root.trayItemValues.indexOf(root.activeTrayItem) === -1))
      root.close()
    root.settlePending()
  }

  // ---- The app menu's rows and keys.
  // LIST (a Quickshell object model's values) as a plain JS array.
  function listOf(list) {
    var out = []
    var count = list ? list.length : 0
    for (var i = 0; i < count; i++)
      out.push(list[i])
    return out
  }

  // A stable serial for ENTRY (see entrySerials).
  function entrySerial(entry) {
    var serials = root.entrySerials
    if (!serials.map.has(entry))
      serials.map.set(entry, serials.next++)
    return serials.map.get(entry)
  }

  // ENTRY (a QsMenuEntry) as TrayLogic's plain MenuEntry: Quickshell's
  // button type and Qt's check state become strings.
  function entryShape(entry) {
    if (!entry)
      return null
    var type = entry.buttonType === QsMenuButtonType.CheckBox ? "check" : entry.buttonType === QsMenuButtonType.RadioButton ? "radio" : "none"
    var state = entry.checkState === Qt.Checked ? "checked" : entry.checkState === Qt.PartiallyChecked ? "partial" : "unchecked"
    return {
      id: root.entrySerial(entry),
      text: entry.text,
      enabled: entry.enabled,
      isSeparator: entry.isSeparator,
      hasChildren: entry.hasChildren,
      buttonType: type,
      checkState: state,
      icon: entry.icon
    }
  }

  // A menu shown afresh (opened, or switched to another item while open):
  // no cursor until the first navigation key, keyboard off, and a click
  // right after it is settled.
  function freshMenuCursor() {
    root.menuCursorActive = false
    root.menuKeyboard = false
    root.clearMenuCursor()
    if (root.trayMenuOpen)
      menuViewItem.noteLayoutChange()
  }

  // Hides the menu cursor (a new level or a new menu starts without one;
  // the keyboard state is kept, so the next arrow picks a row at once).
  function clearMenuCursor() {
    root.menuCursorIndex = -1
    root.menuCursorKey = ""
  }

  // Puts the menu cursor on row INDEX (-1 hides it), keyed by that row.
  function placeMenuCursor(index) {
    var row = index >= 0 ? root.menuRowList[index] : null
    root.menuCursorIndex = row ? index : -1
    root.menuCursorKey = row ? row.key : ""
  }

  // The first key after opening or after pointer use only reveals the
  // cursor: on the row it was on, else on the first selectable row.
  // Returns true when this key was that reveal.
  function revealMenuCursor() {
    if (root.menuCursorActive && root.menuKeyboard)
      return false
    root.menuCursorActive = true
    root.menuKeyboard = true
    if (!CursorLogic.cursorConfirmed(root.menuRowList, root.menuCursorKey, root.menuCursorIndex))
      root.placeMenuCursor(TrayLogic.nextCursor(root.menuRowList, -1, 1))
    return true
  }

  // Keeps the menu cursor on its row's key across a live menu rebuild, and
  // hides it when that row is gone (never adopting the row that slid in).
  function followMenuCursor() {
    if (root.menuCursorIndex < 0)
      return
    var follow = CursorLogic.followCursor(root.menuRowList, root.menuCursorKey, root.menuCursorIndex)
    if (follow.confirmed)
      root.menuCursorIndex = follow.index
    else
      root.clearMenuCursor()
  }

  // Activates row INDEX of menuRowList if it still holds KEY: drills into
  // an entry with children, else triggers the entry and closes (stock).
  // Refused when the row changed or can't be activated.
  function activateMenuRow(index, key) {
    var rows = root.menuRowList
    if (!CursorLogic.rowKeyMatches(rows, index, key))
      return
    var row = rows[index]
    if (!row.selectable)
      return
    var entry = root.currentEntries[row.index]
    if (!entry)
      return
    if (row.hasChildren) {
      root.enterSubmenu(entry, row.label)
    } else {
      entry.triggered()
      root.close()
    }
  }

  // Goes back one menu level; nothing at the root.
  function menuBack() {
    if (root.submenuDepth > 0)
      root.leaveSubmenu()
  }

  // Arrow keys in the menu: up/down move (wrapping, skipping separators and
  // disabled rows), right drills into the cursor's submenu, left goes back.
  function menuMove(dx, dy) {
    menuViewItem.disarmPointer()
    if (root.revealMenuCursor())
      return
    if (dy !== 0) {
      root.placeMenuCursor(TrayLogic.nextCursor(root.menuRowList, root.menuCursorIndex, dy))
    } else if (dx > 0) {
      var row = root.menuRowList[root.menuCursorIndex]
      if (row && row.hasChildren && CursorLogic.cursorConfirmed(root.menuRowList, root.menuCursorKey, root.menuCursorIndex))
        root.activateMenuRow(root.menuCursorIndex, root.menuCursorKey)
    } else if (dx < 0) {
      root.menuBack()
    }
  }

  // Enter or Space in the menu: acts on the cursor's row once the cursor
  // shows and still holds its key.
  function menuActivate() {
    menuViewItem.disarmPointer()
    if (root.revealMenuCursor())
      return
    if (CursorLogic.cursorConfirmed(root.menuRowList, root.menuCursorKey, root.menuCursorIndex))
      root.activateMenuRow(root.menuCursorIndex, root.menuCursorKey)
  }

  // Typed text in the menu: Backspace goes back; a letter jumps to the next
  // selectable row whose label starts with it (TrayLogic.jumpTo).
  function menuText(text) {
    menuViewItem.disarmPointer()
    if (text.length !== 1 || (text !== "\b" && text.trim() === ""))
      return
    if (root.revealMenuCursor())
      return
    if (text === "\b")
      root.menuBack()
    else
      root.placeMenuCursor(TrayLogic.jumpTo(root.menuRowList, root.menuCursorIndex, text))
  }

  // Carries out one TrayMenuView action: a keyed activate or back. Pointer
  // clicks also wait out stock's level settle. A hover is only the row's
  // own fill: it never moves the cursor or hides the outline.
  function handleMenuAction(name, arg) {
    if (name === "hover")
      return
    var a = arg || ({})
    root.menuKeyboard = false
    if (name === "activate") {
      if (!root.menuLevelSettling)
        root.activateMenuRow(a.index, a.key)
    } else if (name === "back") {
      if (!root.menuLevelSettling)
        root.menuBack()
    }
  }

  // ---- The manage panel's rows and keys.
  // Puts the manage cursor on CURSOR ({row, pill}), keyed by that row.
  function placeManageCursor(cursor) {
    var row = cursor && cursor.row >= 0 ? root.manageRowList[cursor.row] : null
    root.manageCursor = {
      row: row ? cursor.row : -1,
      pill: cursor && cursor.pill === 1 ? 1 : 0
    }
    root.manageCursorKey = row ? row.key : ""
  }

  // The first key after opening or after pointer use only reveals the
  // manage cursor (where it was, else the first row's Pin).
  function revealManageCursor() {
    if (root.manageCursorActive && root.manageKeyboard)
      return false
    root.manageCursorActive = true
    root.manageKeyboard = true
    if (!CursorLogic.cursorConfirmed(root.manageRowList, root.manageCursorKey, root.manageCursor.row))
      root.placeManageCursor({
        row: root.manageRowList.length > 0 ? 0 : -1,
        pill: root.manageCursor.pill
      })
    return true
  }

  // Keeps the manage cursor on its item across a bucket change, and hides
  // it when the item left.
  function followManageCursor() {
    if (root.manageCursor.row < 0)
      return
    var index = TrayLogic.indexOfKey(root.manageRowList, root.manageCursorKey)
    if (index === root.manageCursor.row)
      return
    root.placeManageCursor({
      row: index,
      pill: root.manageCursor.pill
    })
  }

  // Toggles NAME ("pin" or "hide") on manage row INDEX if it still holds
  // KEY; refused otherwise.
  function toggleManageRow(name, index, key) {
    if (!CursorLogic.rowKeyMatches(root.manageRowList, index, key))
      return
    if (name === "pin")
      root.togglePin(key)
    else if (name === "hide")
      root.toggleHide(key)
  }

  // Arrow keys in manage: up/down move between rows (clamped), left/right
  // pick the Pin or Hide pill (TrayLogic.manageMove).
  function manageMove(dx, dy) {
    manageViewItem.disarmPointer()
    if (root.revealManageCursor())
      return
    var key = dy < 0 ? "up" : dy > 0 ? "down" : dx < 0 ? "left" : "right"
    var from = root.manageCursor.row < 0 ? {
      row: 0,
      pill: root.manageCursor.pill
    } : root.manageCursor
    root.placeManageCursor(TrayLogic.manageMove(from, root.manageRowList.length, key))
  }

  // Enter or Space in manage: toggles the chosen pill through the keyed
  // path (never the pill's own activate).
  function manageActivate() {
    manageViewItem.disarmPointer()
    if (root.revealManageCursor())
      return
    if (CursorLogic.cursorConfirmed(root.manageRowList, root.manageCursorKey, root.manageCursor.row))
      root.toggleManageRow(root.manageCursor.pill === 1 ? "hide" : "pin", root.manageCursor.row, root.manageCursorKey)
  }

  // Carries out one TrayManageView action: a keyed pin or hide. A hover
  // is only the pill's own fill: it never moves the cursor or hides the
  // outline.
  function handleManageAction(name, arg) {
    if (name === "hover")
      return
    var a = arg || ({})
    root.manageKeyboard = false
    if (name === "pin" || name === "hide")
      root.toggleManageRow(name, a.index, a.key)
  }

  visible: pinnedItems.length > 0 || drawerCount > 0
  clip: false
  implicitWidth: root.vertical ? root.barSize : trayContent.implicitWidth
  implicitHeight: root.vertical ? trayContent.implicitHeight : root.barSize

  onMenuRowListChanged: root.followMenuCursor()
  onManageRowListChanged: root.followManageCursor()
  onTrayItemValuesChanged: root.pruneVanished()
  onAllItemsChanged: root.pruneVanished()
  onActiveTrayItemChanged: if (!root.activeTrayItem && root.trayMenuOpen)
    root.close()
  onPinnedIdsChanged: root.noteSettingsChange()
  onHiddenIdsChanged: root.noteSettingsChange()
  // The bucket lists changing moves the manage rows' state under a still
  // pointer: stamp the manage view's layout.
  onPinnedItemsChanged: manageViewItem.noteLayoutChange()
  onDrawerItemsChanged: manageViewItem.noteLayoutChange()
  // A fresh menu shows no cursor until the first navigation key, and a
  // click right after it opens is settled.
  onTrayMenuOpenChanged: root.freshMenuCursor()
  // The same for the manage panel.
  onManagePopupOpenChanged: {
    root.manageCursorActive = false
    root.manageKeyboard = false
    root.placeManageCursor(null)
    if (root.managePopupOpen)
      manageViewItem.noteLayoutChange()
  }

  Behavior on revealProgress {
    NumberAnimation {
      duration: root.animationDuration
      easing.type: Easing.OutCubic
    }
  }

  Loader {
    id: trayContent
    anchors.fill: parent
    sourceComponent: root.vertical ? verticalTray : horizontalTray
  }

  Component {
    id: horizontalTray

    Item {
      id: horizontalTrayRoot

      readonly property int pinnedWidth: pinnedRow.implicitWidth
      // The arrow plus the drawer's revealed part: nothing is reserved for
      // the collapsed drawer, so the widget grows as it slides open.
      readonly property int drawerBlockWidth: root.allItems.length > 0 ? expandIcon.implicitWidth + Math.round(root.revealExtent) : 0

      implicitWidth: pinnedWidth + drawerBlockWidth
      implicitHeight: root.barSize

      // No containment mask: the widget reserves no empty area for the
      // collapsed drawer any more, so its whole box is live.

      Item {
        id: drawerArea
        x: 0
        width: horizontalTrayRoot.drawerBlockWidth
        height: root.barSize
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.drawerHovered = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          x: 0
          text: "\uf053"
          onPressed: function (button: int) {
            root.arrowPressed(button)
          }
          Component.onCompleted: root.drawerArrow = expandIcon
          Component.onDestruction: if (root && root.drawerArrow === expandIcon)
            root.drawerArrow = null
        }

        Item {
          id: trayClip
          x: expandIcon.width
          anchors.verticalCenter: parent.verticalCenter
          width: Math.round(root.revealExtent)
          height: root.barSize
          clip: true

          // Pinned to the clip's far edge, so the widening clip uncovers
          // the icons from the pinned side.
          Row {
            id: trayIcons
            x: trayClip.width - root.drawerExtent
            anchors.verticalCenter: parent.verticalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Row {
        id: pinnedRow
        x: drawerArea.x + horizontalTrayRoot.drawerBlockWidth
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.trayItemGap
        leftPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Component {
    id: verticalTray

    Item {
      id: verticalTrayRoot

      readonly property int pinnedHeight: pinnedCol.implicitHeight
      // The arrow plus the drawer's revealed part, as the horizontal tray.
      readonly property int drawerBlockHeight: root.allItems.length > 0 ? expandIcon.implicitHeight + Math.round(root.revealExtent) : 0

      implicitWidth: root.barSize
      implicitHeight: pinnedHeight + drawerBlockHeight

      // No containment mask, as the horizontal tray.

      Item {
        id: drawerArea
        y: 0
        width: root.barSize
        height: verticalTrayRoot.drawerBlockHeight
        visible: root.allItems.length > 0

        HoverHandler {
          onHoveredChanged: root.drawerHovered = hovered
        }

        BarIconButton {
          id: expandIcon
          bar: root.bar
          width: implicitWidth
          height: implicitHeight
          y: 0
          text: "\uf053"
          textRotation: 90
          onPressed: function (button: int) {
            root.arrowPressed(button)
          }
          Component.onCompleted: root.drawerArrow = expandIcon
          Component.onDestruction: if (root && root.drawerArrow === expandIcon)
            root.drawerArrow = null
        }

        Item {
          id: trayClip
          y: expandIcon.height
          anchors.horizontalCenter: parent.horizontalCenter
          width: root.barSize
          height: Math.round(root.revealExtent)
          clip: true

          // Pinned to the clip's far edge, as the horizontal tray.
          Column {
            id: trayIcons
            y: trayClip.height - root.drawerExtent
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: root.trayItemGap
            layer.enabled: true

            Repeater {
              model: root.drawerItems
              TrayItem {}
            }
          }
        }
      }

      Column {
        id: pinnedCol
        y: drawerArea.y + verticalTrayRoot.drawerBlockHeight
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: root.trayItemGap
        topPadding: root.pinnedItems.length > 0 && root.allItems.length > 0 ? root.trayJoinGap : 0
        Repeater {
          model: root.pinnedItems
          TrayItem {}
        }
      }
    }
  }

  Aranea.KeyboardPanelFrame {
    id: managePopup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.managePopupOpen
    contentWidth: managePopup.fittedContentWidth(Style.space(340))
    contentHeight: managePopup.fittedContentHeight(manageViewItem.implicitHeight)
    onCloseRequested: root.close()
    onMoveRequested: function (dx: int, dy: int) {
      root.manageMove(dx, dy)
    }
    onActivateRequested: root.manageActivate()

    TrayManageView {
      id: manageViewItem
      width: parent.width
      view: root.manageView
      onAction: function (name: string, arg: var) {
        root.handleManageAction(name, arg)
      }
    }
  }

  QsMenuOpener {
    id: trayMenuOpener
    menu: root.activeTrayItem ? root.activeTrayItem.menu : null
  }

  Aranea.KeyboardPanelFrame {
    id: trayMenuPopup
    anchorItem: root.activeTrayAnchor || root
    owner: root
    bar: root.bar
    open: root.trayMenuOpen
    // The card fades out over 140ms (the frame stays visible for that whole
    // time, see KeyboardPanel's own visible: open || card.opacity > 0), so
    // resetting on "open" would swap a live submenu for the root menu
    // mid-fade: a visible flash, and a resize/reposition if the two have
    // different geometry. Wait for the fade to actually finish. Switching to
    // a different tray item still resets immediately, from openTrayMenu()
    // itself.
    onVisibleChanged: if (!visible)
      root.resetTrayMenu()
    contentWidth: trayMenuPopup.fittedContentWidth(Style.space(320))
    contentHeight: trayMenuPopup.fittedContentHeight(menuViewItem.implicitHeight)
    onCloseRequested: root.close()
    onMoveRequested: function (dx: int, dy: int) {
      root.menuMove(dx, dy)
    }
    onActivateRequested: root.menuActivate()
    onTextKey: function (text: string) {
      root.menuText(text)
    }
    // The key catcher takes "x" for delete; in the menu it is a letter.
    onDeleteRequested: root.menuText("x")

    TrayMenuView {
      id: menuViewItem
      width: parent.width
      view: root.menuView
      onAction: function (name: string, arg: var) {
        root.handleMenuAction(name, arg)
      }
    }
  }

  IpcHandler {
    target: "araneadev.tray"

    // Opens the manage popup at the tray.
    function manage(): void {
      root.openManage()
    }
    // Opens the app menu of the pinned item at INDEX, or of the drawer item
    // past the pinned ones; out of range is a no-op.
    function menu(index: int): void {
      root.openMenuAt(index)
    }
    // Closes either popup and lets a click-held drawer go.
    function close(): void {
      root.drawerClickedOpen = false
      root.close()
    }
  }

  // Renders a tray icon, recoloring symbolic icons to the bar foreground so
  // they stay visible on any theme (a raw symbolic icon keeps its baked-in
  // fill and disappears against a matching background).
  component TrayIcon: Item {
    id: trayIconRoot
    required property var icon
    readonly property bool symbolic: root.iconIsSymbolic(icon)

    Image {
      id: trayIconImage
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels: IconImage uses the logical size,
      // which leaves PNG icons upscaled and blurry on HiDPI displays.
      sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
      source: root.trayIconSource(trayIconRoot.icon)
      // Kept as a hidden layer so the effect can sample it as a texture.
      visible: !trayIconRoot.symbolic
      layer.enabled: trayIconRoot.symbolic
    }

    MultiEffect {
      anchors.fill: trayIconImage
      source: trayIconImage
      visible: trayIconRoot.symbolic
      colorization: 1.0
      colorizationColor: root.foreground
    }
  }

  component TrayItem: Item {
    id: trayItemRoot

    required property var modelData

    visible: modelData.status !== Status.Passive
    implicitWidth: visible ? root.trayItemExtent : 0
    implicitHeight: visible ? root.trayItemExtent : 0

    function displayMenu(mouse) {
      root.openTrayMenu(trayItemRoot.modelData, trayItemRoot, mouse)
    }

    Component.onCompleted: root.trayItemViews.push(trayItemRoot)
    Component.onDestruction: {
      if (!root || !root.trayItemViews)
        return
      var at = root.trayItemViews.indexOf(trayItemRoot)
      if (at !== -1)
        root.trayItemViews.splice(at, 1)
    }

    Rectangle {
      // The selected highlight: the item whose menu is open.
      objectName: "selectedFill"
      anchors.fill: parent
      color: Aranea.DesignTokens.selectedFill
      visible: root.trayMenuOpen && root.activeTrayItem === trayItemRoot.modelData
    }
    Aranea.HoverTint {}
    TrayIcon {
      anchors.centerIn: parent
      width: Style.space(12)
      height: Style.space(12)
      icon: trayItemRoot.modelData.icon
    }

    MouseArea {
      id: mouseArea
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      // qmllint disable missing-property
      onEntered: if (root.bar)
        root.bar.showTooltip(trayItemRoot, root.trayTooltip(trayItemRoot.modelData))
      onExited: if (root.bar)
        root.bar.hideTooltip(trayItemRoot)
      // qmllint enable missing-property
      onPressed: function (mouse: MouseEvent) {
        if (mouse.button === Qt.RightButton) {
          trayItemRoot.displayMenu(mouse)
          mouse.accepted = true
        }
      }
      onClicked: function (mouse: MouseEvent) {
        if (mouse.button === Qt.RightButton) {
          mouse.accepted = true
        } else if (mouse.button === Qt.MiddleButton) {
          trayItemRoot.modelData.secondaryActivate()
        } else if (trayItemRoot.modelData.onlyMenu) {
          trayItemRoot.displayMenu(mouse)
        } else {
          trayItemRoot.modelData.activate()
        }
      }
      onWheel: function (wheel: WheelEvent) {
        trayItemRoot.modelData.scroll(wheel.angleDelta.y, false)
      }
    }

    readonly property bool tooltipHovered: visible && opacity > 0 && mouseArea.containsMouse
  }
}
