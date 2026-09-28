// The notification toasts: one PanelWindow per output (Variants on
// Quickshell.screens) holding the stacked toast cards. Service.qml creates
// it with itself as `root` unless windowEnabled is off (tests).
//
// Layer is Overlay, exclusionMode Ignore, no keyboard focus: popups are
// passive surfaces and must never steal input from the focused application.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Commons

import "components"
import "NotificationLogic.js" as NotificationLogic

Scope {
  id: toasts

  // The notification service (Service.qml): popup model, timing and actions.
  required property var root

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: popupWindow
      required property var modelData
      screen: modelData
      visible: toasts.root.popupModel.count > 0

      WlrLayershell.namespace: "omarchy-notifications"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      exclusionMode: ExclusionMode.Ignore
      color: "transparent"

      readonly property var popupPlacement: NotificationLogic.popupPlacement(toasts.root.barPosition, toasts.root.barClearance, Style.gapsOut)

      // Full-screen, fixed-size surface (like the OSD overlay). Adding or
      // removing a toast changes only the content inside; the Wayland surface
      // never resizes, so the compositor can't briefly scale a stale buffer --
      // which is what stretched/squished the cards during count changes.
      anchors {
        top: true
        bottom: true
        left: true
        right: true
      }

      // Keep the surface click-through except over the toast column, so the
      // rest of the (invisible) full-screen overlay never eats input.
      mask: Region {
        item: popupColumn
      }

      ColumnLayout {
        id: popupColumn
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: popupWindow.popupPlacement.margins.top
        anchors.rightMargin: popupWindow.popupPlacement.margins.right
        spacing: Style.space(8)

        Repeater {
          model: toasts.root.popupModel

          // The delegate is a slot Item that owns lifetime timer state. The
          // actual visuals live in NotificationCard, which the history panel
          // also reuses.
          delegate: Item {
            id: cardSlot
            required property int index
            required property string app
            required property string appIcon
            required property string summary
            required property string body
            required property string image
            required property string glyph
            required property int urgency
            required property double expireTimeout
            required property double timestamp
            required property int originalId
            // The notification service, read once so the delegate's calls stay short.
            readonly property var svc: toasts.root

            // Each card sizes itself based on mode (text vs media); the slot
            // tracks the card so the column auto-fits to whichever is widest.
            Layout.preferredWidth: card.implicitWidth
            Layout.alignment: Qt.AlignRight
            implicitHeight: card.implicitHeight

            readonly property real lifetime: cardSlot.svc.durationFor(cardSlot.urgency, cardSlot.expireTimeout)
            property real remainingLifetime: 1.0
            // Key shared by this toast's copies on every screen.
            readonly property string holdKey: String(cardSlot.timestamp) + "-" + String(cardSlot.originalId)
            // This copy is hovered or dragged.
            readonly property bool held: card.hovered || card.dragging
            onHeldChanged: cardSlot.svc.holdPopup(cardSlot.holdKey, cardSlot.held)
            Component.onDestruction: if (cardSlot.held)
              cardSlot.svc.holdPopup(cardSlot.holdKey, false)
            readonly property bool ticking: cardSlot.lifetime > 0 && !cardSlot.svc.popupHeld(cardSlot.holdKey)

            // A client updating this notification in place rewrites the row
            // under the card (see refreshPopup). New text deserves a full look,
            // so the countdown starts over instead of running out the clock the
            // superseded text was already most of the way through. Delegates
            // keep their own row as the model changes around them, so only a
            // real content change lands here.
            onSummaryChanged: cardSlot.remainingLifetime = 1.0
            onBodyChanged: cardSlot.remainingLifetime = 1.0
            onImageChanged: cardSlot.remainingLifetime = 1.0

            Timer {
              interval: 50
              repeat: true
              running: cardSlot.ticking
              onTriggered: {
                if (cardSlot.lifetime <= 0)
                  return
                cardSlot.remainingLifetime -= 50.0 / cardSlot.lifetime
                if (cardSlot.remainingLifetime <= 0) {
                  cardSlot.remainingLifetime = 0
                  cardSlot.svc.expirePopup(cardSlot.index)
                }
              }
            }

            NotificationCard {
              id: card
              anchors.right: parent.right
              app: cardSlot.app
              appIcon: cardSlot.appIcon
              summary: cardSlot.summary
              body: cardSlot.body
              image: cardSlot.image
              urgency: cardSlot.urgency
              cornerRadius: cardSlot.svc.cornerRadius
              fontFamily: cardSlot.svc.shell && cardSlot.svc.shell.bar ? cardSlot.svc.shell.bar.fontFamily : ""
              glyph: cardSlot.glyph

              motionEnabled: cardSlot.svc.motionEnabled

              onCloseRequested: cardSlot.svc.dismissPopup(cardSlot.index)
              onSwipeDismissed: cardSlot.svc.dismissPopup(cardSlot.index)
              onCardClicked: cardSlot.svc.invokePopupDefault(cardSlot.index)
            }
          }
        }
      }
    }
  }
}
