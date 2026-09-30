// Shared Aranea component contract: visual primitives retain the host shell's
// border implementation while exposing the theme's common surface defaults.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Shared
import qs.Commons

ShellRoot {
  QmlTest {
    id: t
  }

  Shared.SurfaceCard {
    id: card
    width: 120
    height: 80
    surface: "tooltip"
    borderColor: Color.tooltip.border
  }

  Shared.StatusRail {
    id: rail
    railColor: Color.accent
  }

  Shared.StatusTextPair {
    id: pair
    title: "TITLE"
    subtitle: "SUBTITLE"
    subtitleElide: Text.ElideRight
  }

  Shared.EmptyState {
    id: empty
    icon: "󰈉"
    message: "No matches"
  }

  Shared.KeyboardInputFrame {
    id: keyboardInput
    width: 120
    height: 80
  }

  Shared.BrandHeader {
    id: brandHeader
    title: "TITLE"
    subtitle: "SUBTITLE"
    counts: "3 ITEMS"
  }

  Shared.StatusRow {
    id: statusRow
    title: "STATUS"
    subtitle: "DETAIL"
    highlighted: true
    clickable: true
  }

  Shared.StatusRow {
    id: trailingRow
    width: 300
    title: "STATUS"
    Text {
      id: trailingValue
      text: "WARN"
    }
  }

  Shared.EmptyState {
    id: inkEmpty
    width: 400
    height: 200
    icon: "󰈉"
    message: "No matches"
  }

  TextMetrics {
    id: inkProbe
    font.family: inkEmpty.fontFamily
    font.pixelSize: inkEmpty.iconSize
    text: inkEmpty.icon
  }

  Item {
    id: inkContainer
    width: 200
    height: 90

    Shared.InkText {
      id: inkCenterText
      y: 0
      x: 60
      width: 80
      text: "\uF489"
      font.family: Style.font.family
      font.pixelSize: 24
      horizontalAlignment: Text.AlignHCenter
    }

    Shared.InkText {
      id: inkLeftText
      y: 30
      x: 40
      text: "\uF489"
      font.family: Style.font.family
      font.pixelSize: 24
      horizontalAlignment: Text.AlignLeft
    }

    Shared.InkText {
      id: inkRightText
      y: 60
      x: 20
      width: 80
      text: "\uF489"
      font.family: Style.font.family
      font.pixelSize: 24
      horizontalAlignment: Text.AlignRight
    }
  }

  TextMetrics {
    id: inkTextProbe
    font: inkCenterText.font
    text: inkCenterText.text
  }

  Component.onCompleted: {
    t.check(Shared.RuntimePaths.home.length > 0, "runtime paths expose the home directory")
    t.equal(Shared.RuntimePaths.motionStatePath, Shared.RuntimePaths.araneaStateRoot + "/motion", "motion path derives from the Aranea state root")
    t.equal(Shared.RuntimePaths.themeRoot, Shared.RuntimePaths.omarchyStateRoot + "/current/theme", "theme paths derive from the Omarchy state root")
    t.check(Shared.RuntimePaths.brandingMarksPath.endsWith("/omarchy/current/theme/branding/marks/"), "branding marks use the current theme path")
    t.check(Shared.RuntimePaths.glyphUrl.startsWith("file://"), "branding glyph exposes a file URL")
    t.equal(Shared.RuntimePaths.glyphUrl, "file://" + Shared.RuntimePaths.brandingRoot + "/brand.svg", "branding glyph URL uses the generated brand asset")
    t.equal(Shared.RuntimePaths.emojiRecentsPath, Shared.RuntimePaths.araneaStateRoot + "/emoji-recent.json", "emoji recents use the shared Aranea state root")
    t.equal(Shared.RuntimePaths.rebootRequiredPath, Shared.RuntimePaths.omarchyStateRoot + "/reboot-required", "reboot marker uses the shared Omarchy state root")
    t.equal(Shared.MotionState.statePath, Shared.RuntimePaths.motionStatePath, "motion state uses the shared runtime path")
    t.check(typeof Shared.MotionState.motionEnabled === "boolean", "motion state exposes a boolean preference")
    t.equal(card.radius, Style.cornerRadius, "surface cards use the shared corner radius")
    t.equal(card.borderWidth, Shared.DesignTokens.borderWidth, "surface cards use the shared border width")
    t.equal(card.contentPadding, 0, "surface cards default to no content padding")
    t.equal(card.cornerRadius, Style.cornerRadius, "surface cards expose configurable corner radius")
    t.equal(Shared.DesignTokens.cornerRadius, Style.cornerRadius, "design tokens expose the canonical corner radius")
    t.equal(Shared.DesignTokens.borderWidth, Math.max(1, Style.space(2)), "the shared border width is the host panel frame width")
    t.equal(Shared.DesignTokens.foreground, Color.foreground, "design tokens expose the canonical foreground")
    t.equal(Shared.DesignTokens.motionEnabled, Shared.MotionState.motionEnabled, "design tokens follow the shared motion state")
    t.equal(rail.implicitWidth, Style.space(2), "status rails use the shared compact width")
    t.equal(pair.title, "TITLE", "status text pairs expose their title")
    t.equal(pair.subtitle, "SUBTITLE", "status text pairs expose their subtitle")
    t.equal(empty.icon, "󰈉", "empty states expose their icon")
    t.equal(empty.message, "No matches", "empty states expose their message")
    t.equal(brandHeader.title, "TITLE", "brand headers expose their title")
    t.equal(brandHeader.subtitle, "SUBTITLE", "brand headers expose their subtitle")
    t.equal(brandHeader.counts, "3 ITEMS", "brand headers expose optional counts")
    t.equal(statusRow.title, "STATUS", "status rows expose their title")
    t.equal(statusRow.subtitle, "DETAIL", "status rows expose their subtitle")
    t.check(statusRow.highlighted, "status rows expose highlight state")
    t.check(statusRow.clickable, "status rows expose click capability")

    t.step(50, function () {
      var right = trailingValue.mapToItem(trailingRow, trailingValue.width, 0).x
      t.equal(Math.round(right), 300, "status row trailing content ends on the row's right edge")

      var column = inkEmpty.children[0]
      var glyph = null
      for (var i = 0; i < column.children.length; i++)
        if (column.children[i].text === inkEmpty.icon)
          glyph = column.children[i]
      // AlignHCenter paints the advance centred in the item; mapToItem adds the ink shift.
      var origin = glyph.mapToItem(inkEmpty, (glyph.width - inkProbe.advanceWidth) / 2, 0).x
      var inkCentre = origin + inkProbe.tightBoundingRect.x + inkProbe.tightBoundingRect.width / 2
      t.check(Math.abs(inkCentre - inkEmpty.width / 2) <= 0.5, "empty-state icon ink is centred: " + inkCentre)
      t.check(inkEmpty.implicitHeight > 0, "empty states report their content height")

      var inkAdvance = inkTextProbe.advanceWidth
      var inkTight = inkTextProbe.tightBoundingRect

      var centerOrigin = inkCenterText.mapToItem(inkContainer, (inkCenterText.width - inkAdvance) / 2, 0).x
      var centerInk = centerOrigin + inkTight.x + inkTight.width / 2
      t.check(Math.abs(centerInk - (inkCenterText.x + inkCenterText.width / 2)) <= 0.5, "InkText centres its ink, not its advance width")

      var leftOrigin = inkLeftText.mapToItem(inkContainer, 0, 0).x
      var leftInk = leftOrigin + inkTight.x
      t.check(Math.abs(leftInk - inkLeftText.x) <= 0.5, "InkText left-aligns its ink, not its advance width")

      var rightOrigin = inkRightText.mapToItem(inkContainer, inkRightText.width - inkAdvance, 0).x
      var rightInk = rightOrigin + inkTight.x + inkTight.width
      t.check(Math.abs(rightInk - (inkRightText.x + inkRightText.width)) <= 0.5, "InkText right-aligns its ink, not its advance width")

      t.done()
    })
  }
}
