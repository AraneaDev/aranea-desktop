// Production menu card shared by the layer window and inert preview host.
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea

Aranea.SurfaceCard {
  id: card
  // Menu composition root supplies state and activation ownership.
  required property var root
  // Shared window pointer gate, null for inert offscreen hosts.
  property var pointerGate: null
  // Result list used by window scroll reveal.
  readonly property alias resultList: resultListComponent.list
  // Restores keyboard focus after navigation or confirmation.
  function focusKeys(): void {
    keyCatcher.forceActiveFocus()
  }
  // Resets the confirmation to its cancel option.
  function resetDeleteConfirm(): void {
    deleteConfirm.selectedIndex = 1
  }
  // Forwards confirmation keys to the existing dialog.
  function deleteConfirmHandleKey(event): bool {
    return deleteConfirm.handleKey(event)
  }
  cornerRadius: card.root.style.cornerRadius
  fillColor: card.root.style.background
  borderSpecOverride: card.root.style.borderSpec
  contentPadding: card.root.style.contentMargin

  MouseArea {
    anchors.fill: parent
    onClicked: {}
  }

  Item {
    id: keyCatcher
    anchors.fill: parent
    z: card.root.appHistory.deleteConfirmOpen ? 20 : 0
    focus: true

    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function (event) {
      card.root.handleKey(event)
    }

    ConfirmDialog {
      id: deleteConfirm

      anchors.fill: parent
      opened: card.root.appHistory.deleteConfirmOpen
      z: 10
      message: "Do you want to uninstall " + ((card.root.appHistory.deleteTarget && card.root.appHistory.deleteTarget.label) || "") + "?"
      confirmText: "Uninstall"
      background: card.root.style.background
      foreground: card.root.style.foreground
      scrim: card.root.style.scrim
      selectedBackground: card.root.style.selectedBackground
      selectedText: card.root.style.selectedText
      fontFamily: card.root.style.fontFamily
      cornerRadius: card.root.style.cornerRadius
      onCanceled: card.root.cancelDelete()
      onConfirmed: card.root.confirmDelete()
    }
  }

  Column {
    anchors.fill: parent
    anchors.topMargin: card.contentTopInset
    anchors.rightMargin: card.contentRightInset
    anchors.bottomMargin: card.contentBottomInset
    anchors.leftMargin: card.contentLeftInset
    spacing: card.root.style.sectionSpacing

    MenuCardChrome {
      width: parent.width
      height: card.root.style.chromeHeight
      sectionSpacing: card.root.style.rootChromeSpacing
      fullRootHeader: card.root.fullRootHeader
      dmenuActive: card.root.dmenuActive
      matchedQuery: !card.root.dmenuActive && card.root.displayModel.count > 0 && card.root.filterText.trim() ? card.root.filterText : ""
      scopedSearch: card.root.scopedSearch
      onSearchEverywhereRequested: card.root.searchEverywhere()
      activeTitle: card.root.item(card.root.activeMenu) ? (card.root.item(card.root.activeMenu).title || card.root.item(card.root.activeMenu).label || "GO") : "GO"
      dmenuPrompt: card.root.dmenu.prompt
      hint: card.root.hint
      rootSearchHint: card.root.fullRootHeader && !card.root.notice ? "Type to search apps, windows and commands" : ""
      workspaceContext: card.root.style.workspaceContext
      clockContext: card.root.style.clockContext
      rootTiles: card.root.style.rootTiles
      brandingMarksPath: card.root.style.brandingMarksPath
      brandingMotifsPath: card.root.style.brandingMotifsPath
      brandingGlyphsPath: card.root.style.brandingGlyphsPath
      foreground: card.root.style.foreground
      contextText: card.root.style.contextText
      selectedText: card.root.style.selectedText
      footerText: card.root.style.footerText
      fontFamily: card.root.style.fontFamily
      menuFontScale: card.root.style.menuFontScale
      menuLetterSpacing: card.root.style.menuLetterSpacing
      motionEnabled: card.root.style.motionEnabled
      rootHeaderHeight: card.root.style.rootHeaderHeight
      headerHeight: card.root.style.headerHeight
      rootContextHeight: card.root.style.rootContextHeight
      rootTileHeight: card.root.style.rootTileHeight
      footerHeight: card.root.style.footerHeight
      pointerGate: card.pointerGate
      layoutChangedAt: card.root.layoutChangedAt
      onTileActivated: function (tile) {
        card.root.activateTile(tile)
      }
    }

    // Input mode: the line that shows what is typed (the filter text).
    Rectangle {
      visible: card.root.mode === "input"
      width: parent.width
      height: card.root.style.inputLineHeight
      radius: card.root.style.cornerRadius
      color: Util.alpha(card.root.style.foreground, 0.04)
      border.width: 1
      border.color: Util.alpha(card.root.style.foreground, card.root.filterText ? 0.22 : 0.10)

      Row {
        anchors.fill: parent
        anchors.leftMargin: Style.space(12)
        anchors.rightMargin: Style.space(12)
        spacing: Style.space(8)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: "›"
          color: card.root.filterText ? card.root.style.selectedText : Util.alpha(card.root.style.foreground, 0.58)
          font.family: card.root.style.fontFamily
          // Host font tokens are exposed through a dynamic QObject map.
          // qmllint disable missing-property
          font.pixelSize: card.root.style.menuFontSize(Style.font.subtitle)
          // qmllint enable missing-property
        }
        Text {
          id: inputValue
          anchors.verticalCenter: parent.verticalCenter
          width: Math.min(implicitWidth, parent.width - x - inputCaret.width - parent.spacing)
          textFormat: Text.PlainText
          text: card.root.filterText || "Type a value…"
          color: card.root.style.foreground
          opacity: card.root.filterText ? 1 : 0.58
          font.family: card.root.style.fontFamily
          // Host font tokens are exposed through a dynamic QObject map.
          // qmllint disable missing-property
          font.pixelSize: card.root.style.menuFontSize(Style.font.subtitle)
          // qmllint enable missing-property
          elide: Text.ElideLeft
        }
        Rectangle {
          id: inputCaret
          anchors.verticalCenter: parent.verticalCenter
          width: Math.max(1, Style.space(2))
          height: inputValue.font.pixelSize + Style.space(2)
          color: card.root.style.selectedText
        }
      }
    }

    Item {
      width: parent.width
      height: card.root.visibleRowsHeight
      MenuResultList {
        id: resultListComponent
        objectName: "menuResults"
        anchors.fill: parent
        // Row highlights bleed into the card padding so row content meets the
        // chrome's content edges.
        anchors.leftMargin: -card.root.style.rowBleed
        anchors.rightMargin: -card.root.style.rowBleed
        rowInset: card.root.style.rowBleed
        foldPeek: card.root.style.rowPeek
        model: card.root.displayModel
        selectedIndex: card.root.selectedIndex
        cursorActive: card.root.outlineShown
        filterText: card.root.filterText
        fullRootHeader: card.root.fullRootHeader
        appLibrary: card.root.appLibrary
        background: card.root.style.background
        foreground: card.root.style.foreground
        selectedBackground: card.root.style.selectedBackground
        selectedText: card.root.style.selectedText
        border: card.root.style.border
        fontFamily: card.root.style.fontFamily
        menuFontScale: card.root.style.menuFontScale
        menuLetterSpacing: card.root.style.menuLetterSpacing
        cornerRadius: card.root.style.cornerRadius
        rowSpacing: card.root.style.rowSpacing
        rowReservedBorderLeft: card.root.style.rowReservedBorderLeft
        rowReservedBorderRight: card.root.style.rowReservedBorderRight
        dividerHeight: card.root.style.dividerHeight
        rowHeightForDetail: card.root.rowHeightForDetail
        pointerGate: card.pointerGate
        layoutChangedAt: card.root.layoutChangedAt
        onRowActivated: function (index, key) {
          card.root.activateKey(index, key)
        }
        onAppContextRequested: function (appId) {
          card.root.toggleFavoriteApp(appId)
        }
      }

      Aranea.EmptyState {
        anchors.fill: parent
        visible: card.root.displayModel.count === 0 && card.root.mode !== "input"
        icon: card.root.emptyStateInfo.icon
        message: card.root.emptyStateInfo.text
        fontFamily: card.root.style.fontFamily
        iconColor: card.root.style.selectedText
        foreground: card.root.style.foreground
        // Host font tokens are exposed through a dynamic QObject map.
        // qmllint disable missing-property
        iconSize: card.root.style.menuFontSize(Style.font.displayLarge)
        // qmllint enable missing-property
        // Host font tokens are exposed through a dynamic QObject map.
        // qmllint disable missing-property
        messageSize: card.root.style.menuFontSize(Style.font.title)
        // qmllint enable missing-property
      }
    }
  }
}
