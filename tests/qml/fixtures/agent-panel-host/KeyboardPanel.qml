// Test-only native window boundary: real panel content and keyboard logic stay unchanged.
import QtQuick

Item {
  // Native anchor/owner API, unused by this offscreen host.
  property Item anchorItem: null
  // Bar identity stays injected by the real plugin.
  property QtObject bar: null
  // Persistent panel lifecycle owner.
  property var owner: null
  // Native border configuration is display-only here.
  property var borderSpec: null
  // Logical open state remains controlled by the actual Panel.
  property bool open: false
  // Shared frame receives its actual keyboard catcher.
  property Item focusTarget: null
  // Fitted content width supplied by the production plugin.
  property real contentWidth: 380
  // Fitted content height supplied by the production plugin.
  property real contentHeight: 640
  // Offscreen host extent for production scroll sizing.
  readonly property real availableCardHeight: 640
  // No native card decoration in this test boundary.
  readonly property real verticalContentInset: 0
  // Native sizing substitution preserves the requested production width.
  function fittedContentWidth(value) {
    return value
  }
  // Native sizing substitution preserves the production content height.
  function fittedContentHeight(value) {
    return Math.min(value, availableCardHeight)
  }
  width: contentWidth
  height: contentHeight
}
