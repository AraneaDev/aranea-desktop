// Only the compositor window boundary is replaced; SpringPanel stays real.
import QtQuick

Item {
  // Injected output geometry and identity; no compositor is contacted.
  property var screen: ({
      width: 1000,
      height: 800,
      name: 'offscreen'
    })
  // Simulates native mapping for the production focus-prime timer.
  property bool backingWindowVisible: visible
  // Accepts the native window fill binding without drawing a new surface.
  property color color: 'transparent'
  // Accepts native exclusion policy without reserving output space.
  property int exclusionMode: 0
  // Retains the real Region object for immediate pointer-release assertions.
  property var mask: null
  component NativeLayer: QtObject {
    // Records the requested compositor surface namespace.
    property string namespace
    // Records the requested layer-shell stacking layer.
    property int layer
    // Records native keyboard ownership without affecting desktop focus.
    property int keyboardFocus
  }
  component NativeAnchors: QtObject {
    // Records whether the native surface spans the top output edge.
    property bool top
    // Records whether the native surface spans the bottom output edge.
    property bool bottom
    // Records whether the native surface spans the left output edge.
    property bool left
    // Records whether the native surface spans the right output edge.
    property bool right
  }
  // Stores native layer-shell namespace, layer and keyboard-focus policy.
  property NativeLayer nativeLayer: NativeLayer {}
  // Stores full-output window anchors independently of Item anchors.
  property NativeAnchors nativeAnchors: NativeAnchors {}
  width: screen ? screen.width : 1000
  height: screen ? screen.height : 800
}
