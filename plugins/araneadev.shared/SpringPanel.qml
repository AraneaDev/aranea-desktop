// Owned adaptation of /usr/share/omarchy/shell/Ui/KeyboardPanel.qml.
// Keeps the installed native placement, focus prime and popout protocol;
// Aranea owns card motion and immediate input-region release on logical close.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

// Layer-shell popup attached to a bar widget icon, designed for
// click-driven AND keyboard-driven panels (e.g. SUPER+CTRL+W summon).
//
// Built on PanelWindow with a brief WlrKeyboardFocus.Exclusive prime followed
// by OnDemand rather than PopupWindow (xdg-popup). The prime acquires focus
// both when the surface maps and when it reopens while still mapped for its
// fade-out. xdg-popups don't get that; they only receive keys after a
// click/hover routes focus through their parent surface; so keyboard-summoned
// popups fell flat without it.
//
// Exclusive would also grant map-time focus, but it makes Hyprland route
// *every* pointer event to the exclusive surface no matter which output
// the cursor is over, which leaves clicks on any other monitor unable to
// reach the dismissal surfaces below.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open,
// padding, margin, contentWidth/Height, centerOnBar, default panelItems.
// Missing on purpose (for now): triggerMode ("hover"), containsMouse.
//
// Positioning: full-screen layer-shell with the card placed inside at
// `cardOrigin`. We use the bar window's height/width for the perpendicular
// axis (away-from-bar) because mapToItem on the anchor returns
// bar-content-relative coords with internal layout offsets baked in
// (e.g. ~13px from the bar's vertical centering of its widget row). The
// parallel axis (along-the-bar) uses the anchor's content x/y since the
// bar spans full screen on that axis.
//
// Outside-click dismissal: an overlay MouseArea catches clicks and forwards
// bar-strip presses to registered buttons. The activePopout coordinator hands
// off to another popup when the user clicks a different bar icon. The native
// input region empties immediately on logical close.
// Quickshell resolves this native interface at runtime.
// qmllint disable uncreatable-type
PanelWindow {
  id: root

  // Bar button whose window and position determine the popup origin.
  required property Item anchorItem
  // Injected bar placement and single-popout coordinator API.
  required property var bar
  // Host panel that owns logical close and coordinator identity.
  property var owner: null
  // Minimum clearance between the card and output edges.
  property int margin: Style.gapsOut
  // Dynamic upstream spacing values used by popup padding.
  readonly property var popupSpacing: Style.spacing
  // Dynamic upstream popup palette used by native card chrome.
  readonly property var popupColors: Color.popups
  // Inset between the card border and hosted panel content.
  property int padding: popupSpacing.popupPadding
  // Requested outer card width after host fitting.
  property int contentWidth: Style.space(280)
  // Requested outer card height after host fitting.
  property int contentHeight: Style.space(200)
  // Per-edge card border resolved from the popup theme.
  property var borderSpec: Border.surfaceSpec("popups", "border", popupColors.border, Math.max(1, Style.space(2)))
  // Centers the card along the bar instead of under its button.
  property bool centerOnBar: false
  // Logical lifecycle state that owns focus, input and coordination.
  property bool open: false
  // Shared presentation preference; injectable by test/capture hosts.
  property bool motionEnabled: MotionState.motionEnabled
  // Reports unsettled presentation for capture readiness.
  readonly property bool motionRunning: motion.running
  // Distance from the bar edge to the card.
  property int gap: Style.gapsOut  // distance between bar edge and panel
  // Tracks an incoming handoff from another bar popup.
  property bool popoutSwitching: false
  // Tracks a host-requested outgoing popup handoff.
  property bool popoutSwitchClosing: false
  // Switches native keyboard policy from Exclusive to OnDemand.
  property bool focusPrimed: false

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. Layer-shell grants focus to the
  // surface during the Exclusive prime, but Qt still needs an active-focus
  // target inside the surface for Keys.onPressed handlers to fire. Schedule
  // the focus through Qt.callLater so it runs after the surface is fully
  // mapped and child items have completed layout.
  property Item focusTarget: null

  // Default content inserted inside the padded native card.
  default property alias panelItems: contentHolder.children

  // Stable host identity registered with the bar coordinator.
  readonly property var coordinatorKey: owner || root
  // Public Quickshell window attached to the anchor button.
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  // Bar edge used by placement and forwarded-click calculations.
  readonly property string barPos: bar ? bar.position : "top"

  // Delegates logical close to the host, falling back to local ownership.
  function close() {
    if (owner && "close" in owner)
      owner.close()
    else
      root.open = false
  }

  // Starts the brief Exclusive phase after the backing window maps.
  function beginFocusPrime() {
    if (open && backingWindowVisible)
      focusPrimeTimer.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  screen: anchorWindow ? anchorWindow.screen : null
  visible: motion.present
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keyboard focus follows `open` (NOT `visible`). The window remains
  // mapped during the fade-out so the opacity animation has something to
  // animate, but keyboard/click ownership must release the moment the
  // logical close fires; otherwise the user is locked out for 140ms.
  //
  // Prime with Exclusive on every open, then settle on OnDemand. Hyprland
  // focuses OnDemand when a surface first maps, but not when an already-mapped
  // fade-out surface changes from None back to OnDemand. Exclusive also takes
  // focus when the previously focused application has constrained the pointer.
  // The brief prime covers both cases; OnDemand then releases compositor-wide
  // pointer hit-testing so clicks can reach the dismissal windows below.
  WlrLayershell.keyboardFocus: open ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive) : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: beginFocusPrime()

  // Full-screen layer-shell. The visible card is positioned inside via
  // `cardOrigin`. The open input region spans the output; bar-strip clicks
  // are forwarded to registered buttons so the coordinator can switch to
  // another popup. Logical close empties that region during decorative frames.
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Clickable region is the whole screen. Clicks in the bar strip are
  // forwarded to registered bar buttons so switching between panel icons
  // works in one click even when the overlay surface is above the bar.
  readonly property real _barStripSize: {
    if (!bar)
      return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  mask: Region {
    width: root.open ? root.screenW : 0
    height: root.open ? root.screenH : 0
  }

  // Track every layout change between the bar's contentItem and the
  // anchor item. `transform` updates whenever any item in that chain
  // moves/resizes, which is what makes the position binding below
  // actually reactive; mapToItem on its own is a one-shot.
  TransformWatcher {
    id: anchorWatcher
    a: root.anchorWindow ? root.anchorWindow.contentItem : null
    b: root.anchorItem
  }

  // Anchor item's position within the bar's content surface. For a
  // full-width top bar, the content x maps directly to screen x; the y
  // returned here has the bar's internal padding baked in (e.g. ~13px
  // from vertical centering of the widget row), which is why `cardOrigin`
  // below uses `barH` for the perpendicular axis instead of this y.
  readonly property point anchorScreenPos: {
    anchorWatcher.transform
    // reactive dependency
    if (!anchorItem || !anchorWindow)
      return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  // Anchor button width used to center horizontal dropdowns.
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  // Anchor button height used to center vertical dropdowns.
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  // Width of the output containing the anchor window.
  readonly property real screenW: screen ? screen.width : 0
  // Height of the output containing the anchor window.
  readonly property real screenH: screen ? screen.height : 0
  // Output width remaining after bar and edge clearances.
  readonly property real availableCardWidth: screenW > 0 ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2)) : 0
  // Output height remaining after bar and edge clearances.
  readonly property real availableCardHeight: screenH > 0 ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2)) : 0
  // Combined top and bottom padding plus card borders.
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  // Fits a requested width within the output and optional host cap.
  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0)
      maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  // Adds vertical chrome to content height and applies output and host caps.
  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0)
      maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  // Desired top-left of the card in screen coordinates. For the
  // perpendicular axis (away-from-bar) we anchor to the bar window's edge
  // directly; not the anchor item's y/x; because mapToItem(barContent)
  // returns coordinates in the bar's content space, which can be offset
  // from the bar surface's screen-anchored corner by internal layout
  // (centering wrappers, padding). The bar's surface IS aligned to its
  // anchored screen edge, so using `barW`/`barH` gives the right edge
  // regardless of how the bar's internal widgets are positioned. For the
  // parallel axis (along the bar) the anchor item's reported position is
  // still consistent with the bar content origin, so it's accurate for
  // centering the card under the icon.
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  // Native bar-window height used for top and bottom attachment.
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  // Clamped card top-left computed from bar edge and anchor position.
  readonly property point cardOrigin: {
    if (!anchorItem || !bar)
      return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }

  // --- popout coordination (same-bar single-popout model) -----------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      if (focusTarget)
        Qt.callLater(function () {
          if (root.open && root.focusTarget)
            root.focusTarget.forceActiveFocus()
        })
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar)
      return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching)
        popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey)
        bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing)
        closeSwitchTimer.restart()
    }
  }

  Timer {
    id: focusPrimeTimer
    // Leave enough time for multiple Qt/Wayland commit cycles after the
    // backing window becomes visible while keeping the compositor-wide
    // Exclusive phase imperceptibly short. This interval is covered by the
    // immediate hide/re-summon acceptance case.
    interval: 75
    onTriggered: if (root.open)
      root.focusPrimed = true
  }

  Timer {
    id: popoutSwitchTimer
    interval: 150
    onTriggered: root.popoutSwitching = false
  }

  Timer {
    id: closeSwitchTimer
    interval: 1
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  // Catches clicks across the output and forwards registered bar presses.
  // The card has its
  // own MouseArea below so clicks on it don't bubble up here. Disabled
  // during the fade-out so the dying overlay doesn't swallow clicks that
  // were meant for the apps behind it.
  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom")
        return py >= root.screenH - root._barStripSize
      if (root.barPos === "left")
        return px <= root._barStripSize
      if (root.barPos === "right")
        return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom")
        return Qt.point(px, py - (root.screenH - root.barH))
      if (root.barPos === "right")
        return Qt.point(px - (root.screenW - root.barW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets)
        return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem)
          continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow))
          continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height)
          return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton)
        return false
      var target = pressTargetAt(px, py)
      if (!target)
        return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function (mouse) {
      hoveringBar = inBarRegion(mouse.x, mouse.y)
    }
    onExited: hoveringBar = false
    onClicked: function (mouse) {
      // While Exclusive is priming, Hyprland may route a click from another
      // output here with translated coordinates. Never interpret that as a
      // click on this output's bar.
      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button))
        return
      root.close()
    }
  }

  // The panel surface only spans the anchor's screen, and the compositor
  // hit-tests pointer input per output, so `dismissArea` above can never see
  // a click on another monitor. Give every other output a transparent twin
  // whose only job is to catch that click. They exist only while the panel is
  // logically open (not during the fade-out, matching `dismissArea.enabled`).
  //
  // Keyboard focus is None: these must catch the pointer without taking focus
  // from the panel when the cursor merely crosses onto their output.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        // Compare by output name: the anchor screen must be known before any
        // twin maps, or a twin would cover the panel's own output.
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  SurfaceMotion {
    id: motion
    opened: root.open
    motionEnabled: root.motionEnabled
  }

  // --- card ----------------------------------------------------------------

  BorderSurface {
    id: card
    objectName: "springPanelCard"
    enabled: root.open
    scale: motion.scale
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    color: root.popupColors.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: motion.opacity

    CircuitFrame {
      anchors.fill: parent
      cornerRadius: card.radius
      visible: card.borderTop + card.borderRight + card.borderBottom + card.borderLeft > 0
    }

    // Swallow clicks on the card so they don't bubble to the dismissal
    // MouseArea behind us.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    Item {
      id: contentHolder
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
    }
  }
}
