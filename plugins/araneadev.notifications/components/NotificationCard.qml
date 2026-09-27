// Notification card. Pure presentational — no service, Notification, or
// ListModel references. The popup container drives lifetime; the history
// panel drives static rendering. Both use the same component: Service.qml's
// toast stack and Panel.qml's center rows (compact).

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui
import "../NotificationLogic.js" as NotificationLogic
import "../InboxLogic.js" as InboxLogic

BorderSurface {
  id: root

  // Sender app name; Chromium-family senders get their origin prefix stripped.
  property string app: ""
  // Sender icon: a themed icon name, an absolute path or a URL.
  property string appIcon: ""
  // Title line, rendered as plain text.
  property string summary: ""
  // Body markup, rendered as sanitized StyledText (NotificationLogic.styledBody).
  property string body: ""
  // Per-notification image; preferred over appIcon in the icon slot.
  property string image: ""
  // Nerd Font glyph rendered in the icon slot when no real icon is set.
  // Used by omarchy-notification-send so user-action toasts (`Silenced
  // notifications` etc.) show their bell/lock/etc. glyph without leaking
  // into the summary text.
  property string glyph: ""
  // NotificationUrgency: Low=0, Normal=1, Critical=2 (upstream).
  property int urgency: 1
  // Arrival time in ms; the card does not read it (callers pass timeLabel).
  property double timestamp: 0
  // Card corner radius.
  property int cornerRadius: 0
  // Center rows: one-line summary, two-line body, relative time and a close
  // button. Toasts keep the full layout and dismiss by right-click or swipe.
  property bool compact: false
  // Relative age shown in compact rows, e.g. "5m".
  property string timeLabel: ""
  // Keyboard cursor in the center.
  property bool selected: false

  // System monospace font injected by the container.
  property string fontFamily: ""

  // True while the pointer is over the card; the toast countdown pauses.
  readonly property bool hovered: hoverTracker.hovered

  // Emitted on right-click or on the compact close button.
  signal closeRequested
  // Emitted on a left click that was not part of a swipe.
  signal cardClicked
  // Emitted once a swipe has carried the card off to the right.
  signal swipeDismissed
  // Off when Aranea motion is disabled: the card leaves without sliding.
  property bool motionEnabled: true
  // Turns swipe-to-dismiss on or off.
  property bool swipeEnabled: true
  // True while a swipe or its settle animation runs; pauses the toast countdown.
  readonly property bool dragging: swipeHandler.active || settleAnimation.running
  // Current horizontal swipe offset in px; the card fades as it grows.
  property real dragOffset: 0
  // Set once the current press moves past the click threshold, so its release
  // is not a click.
  property bool dragMoved: false

  transform: Translate {
    x: root.dragOffset
  }
  opacity: 1 - Math.min(0.85, Math.max(0, root.dragOffset) / Math.max(1, root.width))
  // Prefer per-notification media/avatar data, then fall back to the app icon.
  // The `check` flag avoids Qt's missing-texture placeholder for unknown names.
  readonly property string smallIconSource: image.length > 0 ? image : iconSource(appIcon)
  // The theme's Aranea mark, drawn when there is neither an icon nor a glyph.
  readonly property string araneaGlyphSource: "file://" + (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/omarchy/current/theme/branding/marks/aranea-glyph.svg"
  // True when an omarchy-glyph is set.
  readonly property bool hasGlyph: glyph.length > 0
  // Draw the glyph inline beside the text instead of in the icon slot.
  readonly property bool compactGlyph: NotificationLogic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
  // True when there is an image or a resolvable icon.
  readonly property bool hasSmallIcon: smallIconSource.length > 0
  // True when the summary itself opens with a glyph (NotificationLogic).
  readonly property bool summaryStartsWithGlyph: NotificationLogic.summaryStartsWithGlyph(summary)
  // True when the sanitized body is empty; tightens the vertical padding.
  readonly property bool singleLineToast: sanitizedBody.length === 0
  // Hides the icon slot for a body-less card whose summary already opens with
  // a glyph.
  readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
  // Body with image tags and Chromium origin prefixes removed; the body row
  // shows only when it is non-empty.
  readonly property string sanitizedBody: sanitizeBody(body)
  // The body as rendered: sanitized StyledText with `<br/>` line breaks.
  readonly property string styledBody: NotificationLogic.styledBody(body, app, appIcon)

  // Muted text color: time label, close button, low-urgency accent.
  readonly property color dimColor: Qt.darker(Color.notifications.text, 1.4)
  // Body text color, slightly darker than the summary.
  readonly property color bodyColor: Qt.darker(Color.notifications.text, 1.15)
  // Urgency accent (red, dim or countdown color); nothing in this file reads it.
  readonly property color accentColor: urgency === 2 ? Color.urgent : (urgency === 0 ? dimColor : Color.notifications.countdown)
  // Color of the urgency rail on the card's left edge.
  readonly property color railColor: urgency === 2 ? Color.urgent : (urgency === 0 ? Color.notifications.border : Color.notifications.countdown)
  // Card fill: red-tinted for critical, a light tint on hover, else the theme's.
  readonly property color cardBackground: urgency === 2 ? Util.alpha(Color.urgent, 0.08) : (hovered ? Util.alpha(Color.notifications.countdown, 0.045) : Color.notifications.background)
  // Border: red for critical, the countdown color when selected, else the theme's.
  readonly property var cardBorderSpec: Border.surfaceSpec("notifications", "border", urgency === 2 ? Color.urgent : (selected ? Color.notifications.countdown : Color.notifications.border), Math.max(1, Style.space(1)))

  // Sanitizes a body for this card's sender (NotificationLogic.sanitizeBody).
  function sanitizeBody(s: string): string {
    return NotificationLogic.sanitizeBody(s, app, appIcon)
  }

  // Resolves an icon value to an image source: URLs pass through, absolute paths
  // become file URLs, themed names go through Quickshell.iconPath ("" if unknown).
  function iconSource(icon: string): string {
    var value = String(icon || "")
    if (value.length === 0)
      return ""
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
      return value
    if (value.charAt(0) === "/")
      return Util.fileUrl(value)
    return Quickshell.iconPath(value, true)
  }

  // The center sets width explicitly for compact rows.
  implicitWidth: compact ? 0 : Style.space(380)
  // Add vertical border insets so mainColumn (inset by border on top/left/right)
  // doesn't push content under the bottom edge.
  implicitHeight: mainColumn.implicitHeight + borderTop + borderBottom
  radius: cornerRadius
  color: root.cardBackground
  borderSpec: cardBorderSpec
  clip: true

  // A narrow semantic rail makes urgency legible at a glance without turning
  // every toast into a bright alert card.
  Rectangle {
    anchors.left: parent.left
    anchors.top: parent.top
    anchors.bottom: parent.bottom
    width: Style.space(3)
    color: root.railColor
    opacity: root.urgency === 0 ? 0.55 : 0.9
  }

  HoverHandler {
    id: hoverTracker
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onPressed: root.dragMoved = false
    onClicked: function (mouse) {
      // A swipe that started on the card must never count as a click.
      if (root.dragMoved)
        return
      if (mouse.button === Qt.RightButton)
        root.closeRequested()
      else
        root.cardClicked()
    }
  }

  DragHandler {
    id: swipeHandler
    enabled: root.swipeEnabled
    target: null
    xAxis.enabled: true
    yAxis.enabled: false
    dragThreshold: InboxLogic.CLICK_SUPPRESS_PX
    acceptedButtons: Qt.LeftButton
    onActiveTranslationChanged: {
      if (!active)
        return
      if (InboxLogic.suppressesClick(activeTranslation.x))
        root.dragMoved = true
      root.dragOffset = Math.max(0, activeTranslation.x)
    }
    onActiveChanged: {
      if (active)
        return
      var outcome = InboxLogic.swipeOutcome(root.dragOffset, root.width, centroid.velocity.x)
      root.settle(outcome === "dismiss")
    }
  }

  // Ends a swipe: slides the card off and emits swipeDismissed, or springs it
  // back; instant when motion is off.
  function settle(dismiss: bool): void {
    if (!root.motionEnabled) {
      root.dragOffset = 0
      if (dismiss)
        root.swipeDismissed()
      return
    }
    settleAnimation.to = dismiss ? root.width + Style.space(24) : 0
    settleAnimation.duration = dismiss ? 180 : 120
    settleAnimation.dismissing = dismiss
    settleAnimation.restart()
  }

  NumberAnimation {
    id: settleAnimation
    property bool dismissing: false
    target: root
    property: "dragOffset"
    easing.type: Easing.OutCubic
    onFinished: {
      if (!dismissing)
        return
      root.dragOffset = 0
      root.swipeDismissed()
    }
  }

  ColumnLayout {
    id: mainColumn
    // Inset by the card border so the content doesn't paint over the card's
    // outer border.
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.topMargin: root.borderTop
    anchors.leftMargin: root.borderLeft
    anchors.rightMargin: root.borderRight
    spacing: 0

    // Text content.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: Style.space(12)
      Layout.rightMargin: Style.space(12)
      Layout.topMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      Layout.bottomMargin: root.singleLineToast ? Style.space(7) : Style.space(10)
      spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? Style.space(8) : Style.space(12))

      Item {
        id: smallIconSlot
        Layout.preferredWidth: visible ? (root.compact ? Style.space(28) : Style.space(40)) : 0
        Layout.preferredHeight: visible ? (root.compact ? Style.space(28) : Style.space(40)) : 0
        Layout.alignment: Qt.AlignVCenter
        // Hide the slot when the icon failed to resolve (themed-icon name
        // not in the user's icon theme) AND we don't have a glyph fallback
        // — prevents rendering Qt's pink broken-image placeholder.
        visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph || (!root.hasSmallIcon && !root.hasGlyph)) && (root.hasGlyph || !root.hasSmallIcon || smallIconImage.status !== Image.Error)

        Image {
          anchors.fill: parent
          source: root.araneaGlyphSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          smooth: true
          mipmap: true
          visible: !root.hasSmallIcon && !root.hasGlyph
        }

        Image {
          id: smallIconImage
          anchors.fill: parent
          source: root.smallIconSource
          sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
          sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
          fillMode: Image.PreserveAspectFit
          asynchronous: true
          smooth: true
          visible: !root.hasGlyph || smallIconImage.status === Image.Ready
        }

        // Glyph fallback (Nerd Font character) when no image icon is
        // available. Used by omarchy-notification-send's `-g` flag.
        Text {
          textFormat: Text.PlainText
          anchors.centerIn: parent
          visible: root.hasGlyph && smallIconImage.status !== Image.Ready
          text: root.glyph
          color: Color.notifications.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.displayLarge
        }
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignVCenter
        visible: root.compactGlyph
        text: root.glyph
        color: Color.notifications.text
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Style.space(2)

        Text {
          // The spec defines the summary as a single line of plain text, so
          // AutoText could only ever promote a hostile string to rich text.
          // The body below is StyledText on purpose — see Service.qml's
          // bodyMarkupSupported — and is stripped in NotificationLogic.
          textFormat: Text.PlainText
          Layout.fillWidth: true
          visible: root.summary.length > 0
          text: root.summary
          font.family: root.fontFamily.length > 0 ? root.fontFamily : Style.font.family
          color: Color.notifications.text
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: root.compact ? 1 : 2
        }

        Text {
          Layout.fillWidth: true
          Layout.topMargin: Style.space(2)
          visible: root.sanitizedBody.length > 0
          text: root.styledBody
          textFormat: Text.StyledText
          font.family: root.fontFamily.length > 0 ? root.fontFamily : Style.font.family
          color: root.bodyColor
          font.pixelSize: Style.font.title
          wrapMode: Text.WordWrap
          elide: Text.ElideRight
          maximumLineCount: root.compact ? 2 : 3
        }
      }

      ColumnLayout {
        visible: root.compact
        Layout.alignment: Qt.AlignTop
        spacing: Style.space(4)

        Text {
          Layout.alignment: Qt.AlignRight
          textFormat: Text.PlainText
          text: root.timeLabel
          color: root.dimColor
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Text {
          Layout.alignment: Qt.AlignRight
          textFormat: Text.PlainText
          text: "✕"
          color: closeArea.containsMouse ? Color.notifications.countdown : root.dimColor
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          MouseArea {
            id: closeArea
            anchors.fill: parent
            anchors.margins: -Style.space(4)
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.closeRequested()
          }
        }
      }
    }
  }
}
