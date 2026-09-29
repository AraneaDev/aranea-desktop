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
    t.equal(card.borderWidth, 1, "surface cards keep a one-pixel border")
    t.equal(card.contentPadding, 0, "surface cards default to no content padding")
    t.equal(card.cornerRadius, Style.cornerRadius, "surface cards expose configurable corner radius")
    t.equal(Shared.DesignTokens.cornerRadius, Style.cornerRadius, "design tokens expose the canonical corner radius")
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
    t.done()
  }
}
