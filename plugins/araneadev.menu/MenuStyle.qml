// Style of the Aranea menu: colors, fonts, metrics, branding paths, the root
// tiles and the root context band (workspace and clock). Menu.qml owns one as
// `style`; MenuWindow reads it as root.style.x.
import Quickshell
import Quickshell.Hyprland
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

QtObject {
  id: style

  // Whether the menu is showing; the clock only ticks then.
  property bool opened: false
  // True on the unfiltered root menu, which adds the context band, tiles and footer.
  property bool fullRootHeader: false

  // Font for all menu text; a payload's fontFamily overrides it.
  property string fontFamily: Style.font.menuFamily
  // Directory of the current theme's branding marks (the header logo).
  readonly property string brandingMarksPath: Aranea.RuntimePaths.brandingMarksPath
  // Directory of the current theme's branding motifs (header art, dividers).
  readonly property string brandingMotifsPath: Aranea.RuntimePaths.brandingMotifsPath
  // Directory of the current theme's branding glyphs (status icons).
  readonly property string brandingGlyphsPath: Aranea.RuntimePaths.brandingGlyphsPath

  // Bound to the central [menu] section in shell.toml via Color.qml.
  // Each color already includes its alpha companion (composed in the
  // singleton), so consumers can drop them straight into a Rectangle.
  property color background: Color.menu.background
  // Menu text color.
  property color foreground: Color.menu.text
  // Card border color.
  property color border: Color.menu.border
  // Border spec for the card, from the shell's menu border settings.
  property var borderSpec: Border.surfaceSpec("menu", "border", style.border, Math.max(1, Style.space(1)))
  // Full-screen backdrop color behind the card.
  property color scrim: Color.menu.scrim
  // Keep the new ornamentation derived from the stable shell palette.  The
  // shell's menu parser intentionally exposes only the established surface
  // tokens, so these are composited here instead of reaching for ad-hoc
  // Color.menu members that older shells do not publish.
  property color contextText: Util.alpha(style.foreground, 0.58)
  // Color of the root footer text.
  property color footerText: Util.alpha(style.foreground, 0.58)
  // Background of the cursor row.
  property color selectedBackground: Color.menu.selectedBackground
  // Text color of the cursor row; also tints hovered tiles and the cursor bar.
  property color selectedText: Color.menu.selectedText
  // Border color of the cursor row.
  property color selectedBorder: Color.menu.selectedBorder
  // Border spec for the cursor row.
  property var selectedBorderSpec: Border.surfaceSpec("menu", "selected-border", style.selectedBorder, 0)
  // Left border width of the cursor row, added to every row's content inset.
  readonly property real rowReservedBorderLeft: Border.left(style.selectedBorderSpec)
  // Space the row reserves on its right edge for the selection border.
  readonly property real rowReservedBorderRight: Border.right(style.selectedBorderSpec)
  // Corner radius of the card and its header.
  readonly property int cornerRadius: Math.max(8, Style.space(8))
  // Scale applied to shell font sizes by menuFontSize().
  readonly property real menuFontScale: 1.10
  // Letter spacing for menu labels.
  readonly property real menuLetterSpacing: 0.20
  // Scales a shell font size by menuFontScale, rounded, at least 1.
  function menuFontSize(size: real): int {
    return Math.max(1, Math.round(size * style.menuFontScale))
  }
  // Padding inside the card.
  property int contentMargin: Style.spacing.panelPadding
  // Header height for submenus and dmenu requests.
  property int headerHeight: Math.max(Style.space(46), style.menuFontSize(Style.font.title) + Style.spacing.controlPaddingY * 2)
  // Header height on the unfiltered root menu.
  property int rootHeaderHeight: Math.max(Style.space(68), style.menuFontSize(Style.font.title) + Style.spacing.controlPaddingY * 2)
  // Height of the root tile row.
  property int rootTileHeight: Style.space(96)
  // Height of the root context band (status, workspace, clock).
  property int rootContextHeight: Style.space(20)
  // Height of the root footer.
  property int footerHeight: Style.space(26)
  // Extra card height for the root context band, tiles and footer (0 elsewhere).
  property int rootExtrasHeight: style.fullRootHeader ? style.rootContextHeight + style.rootTileHeight + style.footerHeight + style.contentSpacing * 3 : 0
  // Keep the polished default, while allowing a session-wide reduced-motion
  // override for accessibility and deterministic testing.
  property bool motionEnabled: Aranea.MotionState.motionEnabled
  // Focused workspace label for the root context band.
  readonly property string workspaceContext: Hyprland.focusedWorkspace ? "WORKSPACE " + Hyprland.focusedWorkspace.id : "WORKSPACE —"

  // Minute clock for clockContext; runs only while the menu is open.
  property SystemClock menuClock: SystemClock {
    id: menuClock
    precision: SystemClock.Minutes
    enabled: style.opened
  }
  // HH:mm time shown in the root context band; ticks every minute.
  readonly property string clockContext: Qt.formatDateTime(menuClock.date, "HH:mm")

  // Fixed tiles (Files, Terminal, Setup) shown on the root menu.
  readonly property var rootTiles: [({
        id: "tile.files",
        label: "Files",
        detail: "BROWSE  ·  ^1",
        icon: "󰉋",
        source: "fixed"
      }), ({
        id: "tile.terminal",
        label: "Terminal",
        detail: "EXECUTE  ·  ^2",
        icon: "",
        source: "fixed"
      }), ({
        id: "tile.setup",
        label: "Setup",
        detail: "CONFIGURE  ·  ^3",
        icon: "",
        source: "fixed"
      })]

  // Section spacing on the root menu; also used in the card height math.
  property int contentSpacing: Style.space(12)
  // Vertical spacing between card sections elsewhere.
  property int compactContentSpacing: Style.space(8)
  // Height of a row without a detail line.
  property int baseRowHeight: Math.max(Style.space(40), style.menuFontSize(Style.font.bodySmall) + Style.space(6) * 2)
  // Row-list height when nothing matches.
  property int emptyStateHeight: Style.space(112)
  // Height of a row that shows a detail line.
  property int detailRowHeight: Math.max(Style.space(58), style.menuFontSize(Style.font.bodySmall) + style.menuFontSize(Style.font.caption) + Style.space(7) * 2)
  // How much of the first hidden row stays visible at the fold: enough to
  // read as a cut-off row rather than a bottom border.
  property int rowPeek: Math.round(style.baseRowHeight * 0.55)
  // Gap between rows.
  property int rowSpacing: Style.space(4)
  // Height of the divider before drilldown search results.
  property int dividerHeight: Style.space(20)
}
