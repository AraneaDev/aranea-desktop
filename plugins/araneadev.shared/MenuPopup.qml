// In-window choices menu; hosts own the immutable row model and all actions.
// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import qs.Commons
import "../araneadev.shared" as Aranea

Aranea.SurfaceCard {
  id: menu
  // Rows contain kind, key, label, detail, checked, enabled and tooltip.
  property var entries: []
  // Optional finite host height; overflowing rows stay keyboard reachable.
  property real maximumHeight: Infinity
  // Logical visibility and keyboard input ownership.
  property bool opened: false
  // Current enabled checkbox or action index, or minus one.
  property int cursor: -1
  // Stable selected identity retained across host model replacements.
  property string cursorKey: ''
  // Shared pointer movement policy used by row hover feedback.
  property var pointerGate: null
  // Host-owned checkbox toggles and action requests.
  signal triggered(string key)
  // Closing lets the split control restore keyboard focus.
  signal closed

  // Whether an index names an enabled interactive entry.
  function interactive(index: int): bool {
    var entry = entries ? entries[index] : null
    return !!entry && (entry.kind === 'check' || entry.kind === 'action') && entry.enabled !== false
  }
  // Select an index and remember its stable identity.
  function select(index: int): void {
    cursor = index
    cursorKey = interactive(index) ? String(entries[index].key || '') : ''
    Qt.callLater(revealCursor)
  }
  // Preserve identity on refresh; otherwise choose the first enabled row.
  function repairCursor(): void {
    if (!opened)
      return
    var count = entries ? entries.length : 0
    var first = -1
    for (var i = 0; i < count; i++) {
      if (!interactive(i))
        continue
      if (first < 0)
        first = i
      if (cursorKey && entries[i].key === cursorKey) {
        select(i)
        return
      }
    }
    select(first)
  }
  // Move in either direction without wrapping or visiting disabled rows.
  function move(step: int): void {
    if (step === 0)
      return
    var direction = step > 0 ? 1 : -1
    var count = entries ? entries.length : 0
    var start = cursor < 0 ? (direction > 0 ? 0 : count - 1) : cursor + direction
    for (var i = start; i >= 0 && i < count; i += direction) {
      if (interactive(i)) {
        select(i)
        return
      }
    }
  }
  // Keep the keyboard row within a height-bounded host viewport.
  function revealCursor(): void {
    var row = repeater.itemAt(cursor)
    if (!row)
      return
    if (row.y < viewport.contentY)
      viewport.contentY = row.y
    else if (row.y + row.height > viewport.contentY + viewport.height)
      viewport.contentY = Math.min(Math.max(0, viewport.contentHeight - viewport.height), row.y + row.height - viewport.height)
  }
  // Open at the first enabled entry; focus never waits for presentation.
  function open(): void {
    if (!enabled)
      return
    if (!opened) {
      select(-1)
      opened = true
    }
    forceActiveFocus()
  }
  // Close immediately and return focus through the host's closed handler.
  function close(): void {
    if (opened)
      opened = false
  }
  // Space toggles checks; Enter activates either kind. Hosts update checked.
  function activateCursor(space: bool): void {
    if (!opened || !enabled || !interactive(cursor))
      return
    var entry = entries[cursor]
    if (entry.kind === 'action' && space)
      return
    triggered(String(entry.key || ''))
    if (entry.kind === 'action')
      close()
  }

  objectName: 'splitMenu'
  // In-window overlays cannot blur underlying content; keep the theme RGB opaque.
  fillColor: Qt.rgba(Color.popups.background.r, Color.popups.background.g, Color.popups.background.b, 1)
  visible: opened
  focus: opened
  z: 100
  contentPadding: Style.space(6)
  // Width never depends on wrapped children; hosts may override width.
  implicitWidth: Math.max(1, Style.space(300))
  implicitHeight: rows.implicitHeight + contentTopInset + contentBottomInset
  height: Math.min(implicitHeight, maximumHeight)
  scale: motion.scale
  onEntriesChanged: repairCursor()
  onOpenedChanged: {
    if (opened) {
      repairCursor()
      forceActiveFocus()
    } else {
      closed()
    }
  }
  onEnabledChanged: if (!enabled)
    close()
  Aranea.SurfaceMotion {
    id: motion
    opened: menu.opened
  }
  Keys.onPressed: function (event) {
    if (!menu.opened || !menu.enabled)
      return
    if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
      move(1)
    else if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
      move(-1)
    else if (event.key === Qt.Key_Space)
      activateCursor(true)
    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
      activateCursor(false)
    else if (event.key === Qt.Key_Escape)
      close()
    else
      return
    event.accepted = true
  }
  Flickable {
    id: viewport
    x: menu.contentLeftInset
    y: menu.contentTopInset
    width: Math.max(0, menu.width - menu.contentLeftInset - menu.contentRightInset)
    height: Math.max(0, menu.height - menu.contentTopInset - menu.contentBottomInset)
    contentWidth: width
    contentHeight: rows.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Column {
      id: rows
      width: viewport.width
      spacing: Style.space(2)
      Repeater {
        id: repeater
        model: menu.entries || []
        Item {
          id: row
          required property var modelData
          required property int index
          objectName: 'menuRow'
          width: rows.width
          implicitHeight: modelData.kind === 'separator' ? Style.space(9) : label.implicitHeight + (detail.visible ? detail.implicitHeight : 0) + Style.space(10)
          Aranea.HoverTint {
            active: menu.interactive(row.index)
            pointerGate: menu.pointerGate
          }
          Rectangle {
            objectName: 'cursorOutline'
            anchors.fill: parent
            visible: menu.cursor === row.index && menu.interactive(row.index)
            color: 'transparent'
            border.width: Aranea.DesignTokens.borderWidth
            border.color: Aranea.DesignTokens.accent
            radius: Aranea.DesignTokens.cornerRadius
          }
          Rectangle {
            visible: row.modelData.kind === 'separator'
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: Aranea.DesignTokens.foreground
            opacity: 0.15
          }
          Aranea.UiLabel {
            id: label
            visible: row.modelData.kind !== 'separator'
            x: Style.space(8)
            y: Style.space(5)
            width: Math.max(0, row.width - Style.space(16))
            text: (row.modelData.kind === 'check' ? (row.modelData.checked ? '✓  ' : '☐  ') : '') + (row.modelData.label || '')
            opacity: row.modelData.kind === 'header' ? 0.55 : row.modelData.enabled === false ? 0.45 : 1
            font.bold: row.modelData.kind === 'header'
          }
          Aranea.UiLabel {
            id: detail
            objectName: 'menuDetail'
            visible: !!text && row.modelData.kind !== 'separator'
            anchors.top: label.bottom
            x: Style.space(8) + (row.modelData.kind === 'check' ? Style.space(18) : 0)
            width: Math.max(0, row.width - x - Style.space(8))
            text: row.modelData.detail || (row.modelData.enabled === false ? row.modelData.tooltip || '' : '')
            opacity: Aranea.DesignTokens.secondaryOpacity
          }
          HoverHandler {
            id: hover
          }
          TapHandler {
            enabled: menu.opened && menu.interactive(row.index)
            onTapped: {
              menu.select(row.index)
              menu.activateCursor(row.modelData.kind === 'check')
            }
          }
          ToolTip.visible: hover.hovered && !!row.modelData.tooltip
          ToolTip.text: row.modelData.tooltip || ''
        }
      }
    }
  }
}
