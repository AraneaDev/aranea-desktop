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

    // The legacy inline tree remains as a hidden compatibility fallback while
    // the extracted surface settles; its dynamic token bindings are not lintable.
    // qmllint disable missing-property
    Column {
      visible: false
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      spacing: panel.root.fullRootHeader ? panel.root.contentSpacing : panel.root.compactContentSpacing

      Rectangle {
        width: parent.width
        height: panel.root.fullRootHeader ? panel.root.rootHeaderHeight : panel.root.headerHeight
        radius: panel.root.cornerRadius
        color: "transparent"

        Image {
          opacity: panel.root.fullRootHeader ? (panel.root.headerMarkSettled ? 1 : 0) : 1
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          width: panel.root.fullRootHeader ? Style.space(48) : Style.space(28)
          height: width
          source: "file://" + panel.root.brandingMarksPath + (panel.root.fullRootHeader ? "aranea-primary.svg" : "aranea-glyph.svg")
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          smooth: true
          mipmap: true
          Behavior on opacity {
            enabled: panel.root.motionEnabled
            NumberAnimation {
              duration: 180
              easing.type: Easing.OutCubic
            }
          }
        }

        Image {
          visible: panel.root.fullRootHeader
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(220)
          height: Style.space(68)
          source: "file://" + panel.root.brandingMotifsPath + "menu-network.svg"
          fillMode: Image.PreserveAspectFit
          opacity: 0.24
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          smooth: true
          mipmap: true
        }

        Column {
          anchors.left: parent.left
          anchors.leftMargin: panel.root.fullRootHeader ? Style.space(62) : Style.space(38)
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.space(4)

          Text {
            textFormat: Text.PlainText
            width: parent.width
            text: panel.root.fullRootHeader ? "ARANEA" : panel.root.dmenuActive ? panel.root.dmenuPrompt : "ARANEA / " + (panel.root.item(panel.root.activeMenu) ? (panel.root.item(panel.root.activeMenu).title || panel.root.item(panel.root.activeMenu).label) : "GO")
            color: panel.root.foreground
            font.family: panel.root.fontFamily
            font.pixelSize: panel.root.fullRootHeader ? panel.root.menuFontSize(Style.font.title) : panel.root.menuFontSize(Style.font.body)
            font.weight: Font.Medium
            font.letterSpacing: panel.root.menuLetterSpacing
            elide: Text.ElideRight
          }

          Text {
            visible: true
            textFormat: Text.PlainText
            width: parent.width
            text: panel.root.hint
            color: panel.root.contextText
            font.family: panel.root.fontFamily
            font.pixelSize: panel.root.menuFontSize(Style.font.caption)
            font.weight: Font.Medium
            font.letterSpacing: panel.root.menuLetterSpacing
            elide: Text.ElideRight
          }
        }

        Image {
          visible: panel.root.fullRootHeader
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(64)
          height: Style.space(12)
          source: "file://" + panel.root.brandingMotifsPath + "edge-trace.svg"
          fillMode: Image.PreserveAspectFit
          opacity: 0.55
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          smooth: true
          mipmap: true
        }
      }

      Row {
        visible: panel.root.fullRootHeader
        width: parent.width
        height: panel.root.rootContextHeight
        spacing: Style.spacing.md

        Image {
          width: panel.root.menuFontSize(Style.font.caption)
          height: width
          source: "file://" + panel.root.brandingGlyphsPath + "ready.svg"
          fillMode: Image.PreserveAspectFit
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          smooth: true
          mipmap: true
          anchors.verticalCenter: parent.verticalCenter
        }

        Text {
          text: panel.root.workspaceContext
          color: panel.root.contextText
          font.family: panel.root.fontFamily
          font.pixelSize: panel.root.menuFontSize(Style.font.caption)
          font.weight: Font.Medium
          font.letterSpacing: panel.root.menuLetterSpacing
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          text: "SYSTEM READY"
          color: panel.root.contextText
          font.family: panel.root.fontFamily
          font.pixelSize: panel.root.menuFontSize(Style.font.caption)
          font.weight: Font.Medium
          font.letterSpacing: panel.root.menuLetterSpacing
          verticalAlignment: Text.AlignVCenter
        }

        Text {
          text: panel.root.clockContext
          color: panel.root.contextText
          font.family: panel.root.fontFamily
          font.pixelSize: panel.root.menuFontSize(Style.font.caption)
          font.weight: Font.Medium
          font.letterSpacing: panel.root.menuLetterSpacing
          verticalAlignment: Text.AlignVCenter
        }
      }

      Row {
        visible: panel.root.fullRootHeader
        width: parent.width
        height: panel.root.rootTileHeight
        spacing: Style.spacing.xs

        Repeater {
          model: panel.root.rootTiles

          delegate: MenuRootTile {
            required property var modelData

            opacity: panel.root.fullRootHeader ? 1 : 0
            width: (parent.width - Style.spacing.xs * 2) / 3
            height: panel.root.rootTileHeight
            tileData: modelData
            fontFamily: panel.root.fontFamily
            foreground: panel.root.foreground
            contextText: panel.root.contextText
            selectedText: panel.root.selectedText
            menuFontScale: panel.root.menuFontScale
            menuLetterSpacing: panel.root.menuLetterSpacing
            motionEnabled: panel.root.motionEnabled

            Behavior on opacity {
              enabled: panel.root.motionEnabled
              NumberAnimation {
                duration: 160
                easing.type: Easing.OutCubic
              }
            }

            onActivated: panel.root.activateTile(modelData)
          }
        }
      }

      Rectangle {
        visible: panel.root.fullRootHeader
        width: parent.width
        height: panel.root.footerHeight
        color: "transparent"

        Image {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(8)
          source: "file://" + panel.root.brandingMotifsPath + "node-divider.svg"
          fillMode: Image.PreserveAspectFit
          opacity: panel.root.nodeAlpha
          sourceSize.width: width * Screen.devicePixelRatio
          sourceSize.height: height * Screen.devicePixelRatio
          smooth: true
          mipmap: true
        }

        Text {
          anchors.left: parent.left
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "COMMANDS  ·  QUICK ACCESS  ·  ENTER TO OPEN"
          color: panel.root.footerText
          opacity: 0.9
          font.family: panel.root.fontFamily
          font.pixelSize: panel.root.menuFontSize(Style.font.bodySmall)
          font.weight: Font.Medium
          font.letterSpacing: panel.root.menuLetterSpacing
          elide: Text.ElideRight
        }

        Text {
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          textFormat: Text.PlainText
          text: "ARANEA"
          color: panel.root.selectedText
          opacity: 0.7
          font.family: panel.root.fontFamily
          font.pixelSize: panel.root.menuFontSize(Style.font.caption)
          font.weight: Font.Medium
          font.letterSpacing: panel.root.menuLetterSpacing
        }
      }

      Item {
        width: parent.width
        height: panel.root.visibleRowsHeight

        ListView {
          id: resultList
          anchors.fill: parent
          model: panel.root.displayModel
          clip: true
          spacing: panel.root.rowSpacing
          boundsBehavior: Flickable.StopAtBounds

          section.property: "section"
          section.criteria: ViewSection.FullString
          section.delegate: Item {
            required property string section

            width: ListView.view.width
            height: section === "drilldown" ? panel.root.dividerHeight : 0
            visible: section === "drilldown"

            Rectangle {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(4)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(4)
              anchors.verticalCenter: parent.verticalCenter
              height: Style.spacing.hairline
              color: Util.alpha(panel.root.foreground, 0.2)
            }
          }

          delegate: BorderSurface {
            id: row
            required property int index
            required property string itemId
            required property string kind
            required property string icon
            required property string iconFont
            required property string appIcon
            required property string appId
            required property string label
            required property string target
            required property string detail
            required property string path
            required property string action
            required property int childCount

            readonly property bool hasCursor: panel.root.cursorActive && row.index === panel.root.selectedIndex
            readonly property bool isApp: row.kind === "app"
            readonly property bool hasIcon: row.icon.length > 0 || row.isApp

            width: ListView.view.width
            height: panel.root.rowHeightForDetail(row.detail)
            radius: panel.root.cornerRadius
            color: row.hasCursor ? panel.root.selectedBackground : "transparent"
            borderSpec: row.hasCursor ? panel.root.selectedBorderSpec : Border.none()

            Behavior on color {
              ColorAnimation {
                duration: 140
                easing.type: Easing.OutCubic
              }
            }

            Rectangle {
              visible: row.hasCursor
              width: Style.space(2)
              height: parent.height - Style.space(14)
              radius: Style.space(1)
              color: panel.root.selectedText
              opacity: 0.9
              anchors.left: parent.left
              anchors.leftMargin: panel.root.rowReservedBorderLeft + Style.space(4)
              anchors.verticalCenter: parent.verticalCenter

              Behavior on opacity {
                NumberAnimation {
                  duration: 120
                  easing.type: Easing.OutCubic
                }
              }
            }

            Text {
              id: iconText
              textFormat: Text.PlainText
              visible: row.hasIcon && !row.isApp
              text: row.icon
              color: row.hasCursor ? panel.root.selectedText : panel.root.foreground
              font.family: row.iconFont.length > 0 ? row.iconFont : panel.root.fontFamily
              font.pixelSize: Style.font.iconLarge
              width: Style.space(36)
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
              anchors.left: parent.left
              anchors.leftMargin: panel.root.rowReservedBorderLeft + Style.space(8)
              y: contentColumn.y + labelText.y + (labelText.height - height) / 2
            }

            Image {
              id: appIconImage
              visible: row.isApp
              width: Style.font.iconLarge
              height: Style.font.iconLarge
              fillMode: Image.PreserveAspectFit
              // Decode at physical pixels: a logical-size decode leaves
              // PNG icons upscaled and blurry on HiDPI displays.
              sourceSize.width: width * Screen.devicePixelRatio
              sourceSize.height: height * Screen.devicePixelRatio
              source: row.isApp && panel.root.appLibrary ? panel.root.appLibrary.iconSource(row.appIcon) : ""
              asynchronous: true
              anchors.left: parent.left
              anchors.leftMargin: panel.root.rowReservedBorderLeft + Style.space(8) + (Style.space(36) - width) / 2
              y: contentColumn.y + labelText.y + (labelText.height - height) / 2
            }

            Column {
              id: contentColumn
              anchors.left: row.hasIcon ? iconText.right : parent.left
              anchors.leftMargin: row.hasIcon ? Style.space(6) : panel.root.rowReservedBorderLeft + Style.space(18)
              anchors.right: trail.left
              anchors.rightMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(4)

              Text {
                id: labelText
                textFormat: Text.PlainText
                width: parent.width
                text: row.label
                color: row.hasCursor ? panel.root.selectedText : panel.root.foreground
                font.family: panel.root.fontFamily
                font.pixelSize: panel.root.menuFontSize(Style.font.bodySmall)
                font.weight: Font.Medium
                font.letterSpacing: panel.root.menuLetterSpacing
                elide: Text.ElideRight
              }

              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: row.detail
                visible: (panel.root.fullRootHeader || panel.root.filterText || row.kind === "dmenu") && row.detail.length > 0
                color: row.hasCursor ? panel.root.selectedText : panel.root.foreground
                opacity: row.hasCursor ? 0.7 : 0.52
                font.family: panel.root.fontFamily
                font.pixelSize: panel.root.menuFontSize(Style.font.caption)
                font.weight: Font.Medium
                font.letterSpacing: panel.root.menuLetterSpacing
                elide: Text.ElideRight

                Behavior on opacity {
                  NumberAnimation {
                    duration: 140
                    easing.type: Easing.OutCubic
                  }
                }
              }
            }

            Row {
              id: trail
              width: Style.space(14)
              anchors.right: parent.right
              anchors.rightMargin: panel.root.rowReservedBorderRight + Style.space(8)
              y: contentColumn.y + labelText.y + (labelText.height - height) / 2
              spacing: 0

              Text {
                textFormat: Text.PlainText
                text: row.kind === "menu" || row.kind === "link" ? "›" : ""
                color: row.hasCursor ? panel.root.selectedText : panel.root.foreground
                opacity: row.kind === "menu" || row.kind === "link" ? 0.36 : 0
                font.family: panel.root.fontFamily
                font.pixelSize: panel.root.menuFontSize(Style.font.body)
                font.weight: Font.Normal
                font.letterSpacing: panel.root.menuLetterSpacing
                anchors.verticalCenter: parent.verticalCenter
              }
            }

            MouseArea {
              id: mouseArea
              anchors.fill: parent
              hoverEnabled: true
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              cursorShape: Qt.PointingHandCursor
              onEntered: panel.root.selectFromPointer(row.index, row, {
                x: mouseArea.mouseX,
                y: mouseArea.mouseY
              })
              onPositionChanged: function (mouse) {
                panel.root.selectFromPointer(row.index, row, mouse)
              }
              onClicked: function (mouse) {
                panel.root.cursorActive = true
                panel.root.selectedIndex = row.index
                if (mouse.button === Qt.RightButton && row.isApp) {
                  panel.root.toggleFavoriteApp(row.appId)
                  return
                }
                panel.root.activateIndex(row.index, true)
              }
            }
          }
        }

        // Scroll scrims. The clipped row already marks the fold at rest;
        // these keep both edges honest once the list has been scrolled,
        // when content hides above the card top as well as below. Strength
        // tracks the distance still hidden past each edge rather than
        // animating on a clock, so a programmatic jump (wrapping from the
        // last row back to the first) lands with the fade already applied.
        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.min(Style.space(28), parent.height / 2)
          visible: opacity > 0
          opacity: resultList.contentHeight > resultList.height ? Math.max(0, Math.min(1, (resultList.contentY - resultList.originY) / height)) : 0
          gradient: Gradient {
            GradientStop {
              position: 0
              color: panel.root.background
            }
            GradientStop {
              position: 1
              color: Util.alpha(panel.root.background, 0)
            }
          }
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.min(Style.space(28), parent.height / 2)
          visible: opacity > 0
          opacity: resultList.contentHeight > resultList.height ? Math.max(0, Math.min(1, (resultList.originY + resultList.contentHeight - resultList.height - resultList.contentY) / height)) : 0
          gradient: Gradient {
            GradientStop {
              position: 0
              color: Util.alpha(panel.root.background, 0)
            }
            GradientStop {
              position: 1
              color: panel.root.background
            }
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
            textFormat: Text.PlainText
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
        onTileActivated: function (tile) { panel.root.activateTile(tile) }
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
          onRowHovered: function (index, row, point) { panel.root.selectFromPointer(index, row, point) }
          onRowActivated: function (index, row, button) {
            panel.root.cursorActive = true
            panel.root.selectedIndex = index
            panel.root.activateIndex(index, true)
          }
          onAppContextRequested: function (appId) { panel.root.toggleFavoriteApp(appId) }
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
