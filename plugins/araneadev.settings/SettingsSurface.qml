// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
// Persistent responsive settings content; window owns the summoned surface.
import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Item {
  id: panel
  // Settings entry object supplied by the summoned host.
  required property var root
  // Persistent settings process and state owner.
  readonly property var controller: root.controller
  // Whether category controls belong above the content.
  readonly property bool compact: width < Style.space(720)
  // Time of the last geometry, category, content or scroll change.
  property real layoutChangedAt: 0
  // Close the summoned surface on Escape.
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.close()
      event.accepted = true
    }
  }
  // Scroll a keyboard-focused control into the visible content area.
  function revealFocus(item) {
    if (!item)
      return
    var parent = item.parent
    while (parent && parent !== scroller.contentItem)
      parent = parent.parent
    if (!parent)
      return
    var pos = item.mapToItem(scroller.contentItem, 0, 0)
    if (pos.y < scroller.contentY)
      scroller.contentY = pos.y
    else if (pos.y + item.height > scroller.contentY + scroller.height)
      scroller.contentY = pos.y + item.height - scroller.height
  }
  Connections {
    target: panel.Window.window
    function onActiveFocusItemChanged() {
      panel.revealFocus(panel.Window.window.activeFocusItem)
    }
  }
  // Give the first keyboard target focus on summon.
  function focusKeys() {
    closeButton.forceActiveFocus()
  }
  // Disarm pointer activation after moving or changing content.
  function stampLayout() {
    layoutChangedAt = Date.now()
    pointerGate.reset()
  }
  onWidthChanged: stampLayout()
  onHeightChanged: stampLayout()
  onVisibleChanged: if (visible) {
    stampLayout()
    Qt.callLater(focusKeys)
  }
  Connections {
    target: panel.root
    function onSectionChanged() {
      panel.stampLayout()
      scroller.contentY = 0
      closeButton.forceActiveFocus()
    }
  }
  Connections {
    target: panel.controller
    function onMutationCompleted(operation, args, succeeded) {
      if (operation === 'configure schedule' && succeeded)
        schedulePage.acceptSaved(args)
    }
    function onStateChanged() {
      panel.stampLayout()
    }
  }
  PointerMoveGate {
    id: pointerGate
    referenceItem: card
    property real layoutChangedAt: panel.layoutChangedAt
  }
  Aranea.SurfaceCard {
    id: card
    anchors.fill: parent
    contentPadding: Style.space(24)
    FocusScope {
      anchors.fill: parent
      anchors.margins: Style.space(24)
      focus: true
      Keys.onPressed: function (event) {
        panel.handleKey(event)
      }
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(16)
        RowLayout {
          Layout.fillWidth: true
          Aranea.BrandHeader {
            Layout.fillWidth: true
            title: 'Aranea settings'
            subtitle: 'Your desktop, configured in one place'
            fontFamily: Style.font.menuFamily
          }
          SettingsButton {
            id: closeButton
            text: 'Close'
            pointerGate: pointerGate
            onClicked: panel.root.close()
          }
        }
        RowLayout {
          Layout.fillWidth: true
          visible: !!panel.controller.error
          SettingsLabel {
            Layout.fillWidth: true
            text: panel.controller.error
            color: Aranea.DesignTokens.attention
          }
          SettingsButton {
            text: 'Retry'
            enabled: !panel.controller.pending
            pointerGate: pointerGate
            onClicked: panel.controller.refresh()
          }
        }
        GridLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          columns: panel.compact ? 1 : 2
          rowSpacing: Style.space(16)
          columnSpacing: Style.space(24)
          SettingsNavigation {
            Layout.fillWidth: panel.compact
            Layout.preferredWidth: panel.compact ? -1 : Style.space(168)
            Layout.alignment: Qt.AlignTop
            compact: panel.compact
            selectedSection: panel.root.section
            pointerGate: pointerGate
            onSectionRequested: function (section) {
              panel.root.section = section
            }
          }
          Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: width
            contentHeight: pages.children[pages.currentIndex] ? pages.children[pages.currentIndex].implicitHeight : 0
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: panel.stampLayout()
            StackLayout {
              id: pages
              width: scroller.width
              height: scroller.contentHeight
              currentIndex: ['appearance', 'schedule', 'integrations', 'notifications'].indexOf(panel.root.section)
              AppearancePage {
                Layout.fillHeight: false
                backendState: panel.controller.state
                pending: panel.controller.pending
                pendingKey: panel.controller.pendingKey
                results: panel.controller.results
                errors: panel.controller.itemErrors
                pointerGate: pointerGate
                onRequest: function (operation, args) {
                  panel.controller.request(operation, args)
                }
                onRetryRequested: panel.controller.refresh()
              }
              SchedulePage {
                id: schedulePage
                Layout.fillHeight: false
                backendState: panel.controller.state
                pending: panel.controller.pending
                pendingKey: panel.controller.pendingKey
                result: panel.controller.resultFor('schedule')
                error: panel.controller.errorFor('schedule')
                pointerGate: pointerGate
                onRequest: function (operation, args) {
                  panel.controller.request(operation, args)
                }
                onRetryRequested: panel.controller.refresh()
              }
              IntegrationsPage {
                Layout.fillHeight: false
                backendState: panel.controller.state
                pending: panel.controller.pending
                pendingKey: panel.controller.pendingKey
                results: panel.controller.results
                errors: panel.controller.itemErrors
                pointerGate: pointerGate
                onRequest: function (operation, args) {
                  panel.controller.request(operation, args)
                }
                onRetryRequested: panel.controller.refresh()
              }
              NotificationsPage {
                Layout.fillHeight: false
                notifications: panel.controller.notifications
                pending: panel.controller.pending
                pendingKey: panel.controller.pendingKey
                result: panel.controller.resultFor('dnd')
                error: panel.controller.errorFor('dnd')
                readErrors: panel.controller.notificationErrors
                pointerGate: pointerGate
                onRequest: function (operation, args) {
                  panel.controller.request(operation, args)
                }
                onRetryRequested: panel.controller.refreshNotifications()
              }
            }
          }
        }
        SettingsLabel {
          Layout.fillWidth: true
          text: 'Tab move · Space / Enter select · Esc close'
          opacity: 0.65
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
