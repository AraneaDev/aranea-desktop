// Window of the Aranea menu: the full-screen overlay with the card, header,
// tiles and rows. Menu.qml (the non-visual plugin entry, which holds all
// state and logic) creates it and passes itself as `root`; tests leave it out.

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

PanelWindow {
  id: panel

  // The menu entry (Menu.qml) this window draws; set at creation.
  required property var root

  // Gives the menu's key handler the keyboard focus.
  function focusKeys(): void {
    keyCatcher.forceActiveFocus()
  }

  // Makes the mouse ignore hover until it really moves.
  function disarmPointer(): void {
    pointerGate.reset()
  }

  // Lets the first pointer sample select (a click that opened a submenu).
  function allowInitialPointerSample(): void {
    pointerGate.allowInitialSample()
  }

  // Whether the pointer really moved over item (see PointerMoveGate).
  function pointerMoved(item, mouse): bool {
    return pointerGate.moved(item, mouse)
  }

  // Preselects "cancel" in the uninstall confirmation.
  function resetDeleteConfirm(): void {
    deleteConfirm.selectedIndex = 1
  }

  // Lets the uninstall confirmation handle a key; true when it did.
  function deleteConfirmHandleKey(event): bool {
    return deleteConfirm.handleKey(event)
  }

  // Contain alone parks the cursor row flush with the viewport edge, hiding
  // the neighbor entirely and losing the fold affordance. Keep the next
  // hidden row peeking past the cursor in the direction of travel.
  function revealCursor(): void {
    if (panel.root.displayModel.count === 0)
      return
    resultList.positionViewAtIndex(panel.root.selectedIndex, ListView.Contain)

    var item = resultList.itemAtIndex(panel.root.selectedIndex)
    if (!item)
      return
    var reach = panel.root.rowPeek + panel.root.rowSpacing
    if (panel.root.selectedIndex < panel.root.displayModel.count - 1) {
      var maxY = Math.max(resultList.originY, resultList.originY + resultList.contentHeight - resultList.height)
      var overhang = item.y + item.height + reach - (resultList.contentY + resultList.height)
      if (overhang > 0)
        resultList.contentY = Math.min(resultList.contentY + overhang, maxY)
    }
    if (panel.root.selectedIndex > 0) {
      var underhang = resultList.contentY - (item.y - reach)
      if (underhang > 0)
        resultList.contentY = Math.max(resultList.contentY - underhang, resultList.originY)
    }
  }

  PointerMoveGate {
    id: pointerGate
    referenceItem: card
  }

  visible: panel.root.opened && panel.root.rowsLoaded
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }
  color: "transparent"
  WlrLayershell.namespace: "omarchy-menu"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  // The card opens centered exactly as always. The first search keystroke
  // or submenu move freezes the top line where it currently sits; from
  // then on the card grows and shrinks downward instead of re-centering
  // on every resize, which made the menu jump around. The rows height is
  // frozen at the same moment, so the starting menu also caps how tall the
  // card may grow from there. Closing unfreezes both.
  property int cardTop: -1
  // Rows height frozen with cardTop (the starting menu's height), or -1.
  property int maxRowsHeight: -1
  // Top edge that centres the card vertically.
  readonly property int centeredTop: Math.max(Style.gapsOut, Math.round((height - panel.root.cardHeight) / 2))
  // Where the card's top edge is: frozen, or centred until the first move.
  readonly property int effectiveCardTop: cardTop >= 0 ? cardTop : centeredTop
  // Freezes the card top and rows height at their current values.
  function freezeCardTop() {
    if (visible && cardTop < 0) {
      cardTop = effectiveCardTop
      maxRowsHeight = panel.root.visibleRowsHeight
    }
  }
  onVisibleChanged: if (!visible) {
    cardTop = -1
    maxRowsHeight = -1
  }

  Rectangle {
    anchors.fill: parent
    color: panel.root.scrim
  }

  MouseArea {
    anchors.fill: parent
    onClicked: panel.root.cancel()
  }

  Aranea.SurfaceCard {
    id: card
    width: panel.root.cardWidth
    height: Math.min(panel.root.cardHeight, panel.height - Style.gapsOut - panel.effectiveCardTop)
    cornerRadius: panel.root.cornerRadius
    anchors.horizontalCenter: parent.horizontalCenter
    y: panel.effectiveCardTop
    fillColor: panel.root.background
    borderSpecOverride: panel.root.borderSpec
    contentPadding: panel.root.contentMargin

    MouseArea {
      anchors.fill: parent
      onClicked: {}
    }

    Item {
      id: keyCatcher
      anchors.fill: parent
      z: panel.root.deleteConfirmOpen ? 20 : 0
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function (event) {
        panel.root.handleKey(event)
      }

      ConfirmDialog {
        id: deleteConfirm

        anchors.fill: parent
        opened: panel.root.deleteConfirmOpen
        z: 10
        message: "Do you want to uninstall " + ((panel.root.deleteTarget && panel.root.deleteTarget.label) || "") + "?"
        confirmText: "Uninstall"
        background: panel.root.background
        foreground: panel.root.foreground
        scrim: panel.root.scrim
        selectedBackground: panel.root.selectedBackground
        selectedText: panel.root.selectedText
        fontFamily: panel.root.fontFamily
        cornerRadius: panel.root.cornerRadius
        onCanceled: panel.root.cancelDelete()
        onConfirmed: panel.root.confirmDelete()
      }
    }

    // qmllint enable missing-property
    Column {
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: panel.root.fullRootHeader ? panel.root.contentSpacing : panel.root.compactContentSpacing

      MenuCardChrome {
        width: parent.width
        height: panel.root.fullRootHeader ? panel.root.rootHeaderHeight + panel.root.rootContextHeight + panel.root.rootTileHeight + panel.root.footerHeight : panel.root.headerHeight
        fullRootHeader: panel.root.fullRootHeader
        dmenuActive: panel.root.dmenuActive
        activeTitle: panel.root.item(panel.root.activeMenu) ? (panel.root.item(panel.root.activeMenu).title || panel.root.item(panel.root.activeMenu).label || "GO") : "GO"
        dmenuPrompt: panel.root.dmenuPrompt
        hint: panel.root.hint
        workspaceContext: panel.root.workspaceContext
        clockContext: panel.root.clockContext
        rootTiles: panel.root.rootTiles
        brandingMarksPath: panel.root.brandingMarksPath
        brandingMotifsPath: panel.root.brandingMotifsPath
        brandingGlyphsPath: panel.root.brandingGlyphsPath
        foreground: panel.root.foreground
        contextText: panel.root.contextText
        selectedText: panel.root.selectedText
        footerText: panel.root.footerText
        fontFamily: panel.root.fontFamily
        menuFontScale: panel.root.menuFontScale
        menuLetterSpacing: panel.root.menuLetterSpacing
        motionEnabled: panel.root.motionEnabled
        rootHeaderHeight: panel.root.rootHeaderHeight
        headerHeight: panel.root.headerHeight
        rootContextHeight: panel.root.rootContextHeight
        rootTileHeight: panel.root.rootTileHeight
        footerHeight: panel.root.footerHeight
        onTileActivated: function (tile) {
          panel.root.activateTile(tile)
        }
      }

      Item {
        width: parent.width
        height: panel.root.visibleRowsHeight
        MenuResultList {
          anchors.fill: parent
          model: panel.root.displayModel
          selectedIndex: panel.root.selectedIndex
          cursorActive: panel.root.cursorActive
          filterText: panel.root.filterText
          fullRootHeader: panel.root.fullRootHeader
          appLibrary: panel.root.appLibrary
          background: panel.root.background
          foreground: panel.root.foreground
          selectedBackground: panel.root.selectedBackground
          selectedText: panel.root.selectedText
          border: panel.root.border
          selectedBorderSpec: panel.root.selectedBorderSpec
          fontFamily: panel.root.fontFamily
          menuFontScale: panel.root.menuFontScale
          menuLetterSpacing: panel.root.menuLetterSpacing
          cornerRadius: panel.root.cornerRadius
          rowSpacing: panel.root.rowSpacing
          rowReservedBorderLeft: panel.root.rowReservedBorderLeft
          rowReservedBorderRight: panel.root.rowReservedBorderRight
          dividerHeight: panel.root.dividerHeight
          rowHeightForDetail: panel.root.rowHeightForDetail
          onRowHovered: function (index, row, point) {
            panel.root.selectFromPointer(index, row, point)
          }
          onRowActivated: function (index, row, button) {
            panel.root.cursorActive = true
            panel.root.selectedIndex = index
            panel.root.activateIndex(index, true)
          }
          onAppContextRequested: function (appId) {
            panel.root.toggleFavoriteApp(appId)
          }
        }

        Column {
          anchors.centerIn: parent
          spacing: Style.space(12)
          visible: panel.root.displayModel.count === 0 && panel.root.mode !== "input"
          Text {
            text: panel.root.emptyStateInfo.icon
            color: panel.root.selectedText
            opacity: 0.8
            font.family: panel.root.fontFamily
            font.pixelSize: panel.root.menuFontSize(Style.font.displayLarge)
            horizontalAlignment: Text.AlignHCenter
            width: Style.space(320)
          }
          Text {
            text: panel.root.emptyStateInfo.text
            color: panel.root.foreground
            opacity: 0.7
            font.family: panel.root.fontFamily
            font.pixelSize: panel.root.menuFontSize(Style.font.title)
            horizontalAlignment: Text.AlignHCenter
            width: Style.space(320)
          }
        }
      }
    }
  }
}
