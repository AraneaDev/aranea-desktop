// Host Style.font is a runtime QObject with token properties.
// qmllint disable missing-property
// Persistent responsive settings content; window owns the summoned surface.
import QtQuick
import QtQuick.Controls
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
  // Reduce fixed chrome on short logical screens while retaining full-size controls.
  readonly property bool shortScreen: height < Style.space(400)
  // Scroll offsets retained independently for each persistent page.
  property var pageOffsets: ({})
  // Section whose scroll offset is currently shown.
  property string scrollSection: 'appearance'
  Component.onCompleted: scrollSection = root.section
  // Hidden layers and offscreen content may have no backing keyboard Window.
  function captureFocus() {
    var window = panel.Window.window
    return window ? window.activeFocusItem : null
  }
  // Save local drafts and independent scroll positions without owner reads.
  function captureSnapshot() {
    return {
      pageOffsets: pageOffsets,
      scrollSection: scrollSection,
      contentY: scroller.contentY,
      selectedId: appearancePage.selectedId,
      wallpaperDirty: appearancePage.wallpaperDirty,
      galleryExpanded: appearancePage.galleryExpanded,
      scaleDraft: displayPage.scaleDraft,
      scaleDirty: displayPage.scaleDirty,
      detailsExpanded: displayPage.detailsExpanded,
      scheduleDraft: schedulePage.draft,
      scheduleDirty: schedulePage.dirty
    }
  }
  // Restore local capture state after restoring owner observations and section.
  function captureRestore(saved) {
    appearancePage.selectedId = saved.selectedId
    appearancePage.wallpaperDirty = saved.wallpaperDirty
    appearancePage.galleryExpanded = saved.galleryExpanded
    displayPage.scaleDraft = saved.scaleDraft
    displayPage.scaleDirty = saved.scaleDirty
    displayPage.detailsExpanded = saved.detailsExpanded
    schedulePage.draft = saved.scheduleDraft
    schedulePage.dirty = saved.scheduleDirty
    pageOffsets = saved.pageOffsets
    scrollSection = saved.scrollSection
    scrollTo(saved.contentY)
    Qt.callLater(function () {
      panel.scrollTo(saved.contentY)
    })
  }
  // Reset only capture-local presentation, never apply owner preferences.
  function captureReset(fixture) {
    appearancePage.wallpaperDirty = false
    appearancePage.discardWallpaper()
    appearancePage.galleryExpanded = false
    displayPage.discardScale()
    if (fixture && fixture.displayDraft)
      displayPage.setScaleDraft(fixture.displayDraft)
    displayPage.detailsExpanded = false
    schedulePage.dirty = false
    schedulePage.syncDraft()
    pageOffsets = ({})
    scrollTo(0)
  }
  // Wait for production artwork and settled geometry before full-screen capture.
  function captureReady() {
    function ready(item) {
      if (item instanceof Image && item.visible && item.source.toString() && item.status !== Image.Ready)
        return false
      var children = item.children || []
      for (var i = 0; i < children.length; i++)
        if (!ready(children[i]))
          return false
      return true
    }
    return Date.now() - layoutChangedAt >= 250 && ready(panel)
  }
  // Time of the last geometry, category, content or scroll change.
  property real layoutChangedAt: 0
  // Close the summoned surface on Escape.
  function handleKey(event) {
    if (event.key === Qt.Key_Escape) {
      root.close()
      event.accepted = true
    } else if (event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) {
      scrollTo(scroller.contentY + (event.key === Qt.Key_PageDown ? 1 : -1) * Math.max(Style.space(36), scroller.height * 0.9))
      event.accepted = true
    }
  }
  // Keep explicit scroll requests inside the currently selected page.
  function scrollTo(position) {
    scroller.cancelFlick()
    scroller.contentY = Math.max(0, Math.min(position, Math.max(0, scroller.contentHeight - scroller.height)))
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
      scrollTo(pos.y)
    else if (pos.y + item.height > scroller.contentY + scroller.height)
      scrollTo(pos.y + item.height - scroller.height)
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
      var next = Object.assign({}, panel.pageOffsets)
      next[panel.scrollSection] = scroller.contentY
      panel.pageOffsets = next
      panel.scrollSection = panel.root.section
      Qt.callLater(function () {
        panel.scrollTo(panel.pageOffsets[panel.root.section] || 0)
      })
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
    contentPadding: Style.space(16)
    FocusScope {
      anchors.fill: parent
      anchors.margins: Style.space(panel.shortScreen ? 12 : 16)
      focus: true
      Keys.onPressed: function (event) {
        panel.handleKey(event)
      }
      ColumnLayout {
        anchors.fill: parent
        spacing: Style.space(panel.shortScreen ? 8 : 12)
        RowLayout {
          Layout.fillWidth: true
          Image {
            objectName: 'settingsGlyph'
            visible: !panel.shortScreen
            Layout.preferredWidth: Style.space(18)
            Layout.preferredHeight: Style.space(18)
            source: Aranea.RuntimePaths.glyphUrl
            sourceSize: Qt.size(Style.space(36), Style.space(36))
            fillMode: Image.PreserveAspectFit
          }
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)
            SettingsLabel {
              Layout.fillWidth: true
              text: 'Aranea settings'
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
            }
            SettingsLabel {
              Layout.fillWidth: true
              visible: !panel.shortScreen
              text: panel.controller.showcaseActive ? 'Preview · read-only' : 'Your desktop preferences'
              opacity: 0.65
            }
          }
          SettingsButton {
            id: closeButton
            text: 'Close'
            pointerGate: pointerGate
            onClicked: panel.root.close()
          }
        }
        GridLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          columns: panel.compact ? 1 : 2
          rowSpacing: Style.space(panel.shortScreen ? 8 : 12)
          columnSpacing: Style.space(16)
          SettingsNavigation {
            Layout.fillWidth: panel.compact
            Layout.preferredWidth: panel.compact ? -1 : Style.space(148)
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
            // Reserve a stable scrollbar gutter to avoid width/overflow binding loops.
            contentWidth: Math.max(1, width - Style.space(12))
            contentHeight: scrollContent.implicitHeight
            boundsBehavior: Flickable.StopAtBounds
            onContentYChanged: panel.stampLayout()
            onContentHeightChanged: panel.stampLayout()
            ScrollBar.vertical: ScrollBar {
              objectName: 'settingsScrollBar'
              width: Style.space(8)
              policy: scroller.contentHeight > scroller.height + 1 ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
              contentItem: Rectangle {
                implicitWidth: Style.space(4)
                radius: width / 2
                color: Util.alpha(Color.foreground, 0.45)
              }
              background: Rectangle {
                color: 'transparent'
              }
            }
            Column {
              id: scrollContent
              width: scroller.contentWidth
              spacing: Style.space(16)
              RowLayout {
                width: parent.width
                visible: !!panel.controller.error
                SettingsLabel {
                  Layout.fillWidth: true
                  text: panel.controller.error
                  color: Aranea.DesignTokens.attention
                }
                SettingsButton {
                  objectName: 'settingsRetry'
                  text: 'Retry'
                  enabled: !panel.controller.pending && !panel.controller.showcaseActive
                  pointerGate: pointerGate
                  onClicked: panel.controller.refresh()
                }
              }
              StackLayout {
                id: pages
                width: scroller.contentWidth
                height: pages.children[pages.currentIndex] ? pages.children[pages.currentIndex].implicitHeight : 0
                currentIndex: ['appearance', 'display', 'schedule', 'integrations', 'notifications'].indexOf(panel.root.section)
                AppearancePage {
                  id: appearancePage
                  Layout.fillHeight: false
                  backendState: panel.controller.state
                  displayOnly: panel.controller.showcaseActive
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
                DisplayPage {
                  id: displayPage
                  Layout.fillHeight: false
                  backendState: panel.controller.state
                  displayOnly: panel.controller.showcaseActive
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
                  displayOnly: panel.controller.showcaseActive
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
                  displayOnly: panel.controller.showcaseActive
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
                  objectName: "notificationsPage"
                  Layout.fillHeight: false
                  notifications: panel.controller.notifications
                  displayOnly: panel.controller.showcaseActive
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
        }
        SettingsLabel {
          Layout.fillWidth: true
          text: 'Tab move · Enter select · Esc close'
          opacity: 0.65
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
