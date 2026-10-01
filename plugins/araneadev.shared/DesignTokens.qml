// Canonical semantic design tokens exposed to shared QML components.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  // Primary accent colour.
  readonly property color accent: Color.accent
  // Secondary accent used by selected menu text.
  readonly property color accentSecondary: Color.menu.selectedText
  // Aranea's violet from design/tokens.toml (Omarchy's Color has none): the
  // far end of the Filament's lit strand and the Now playing progress.
  readonly property color strandEnd: "#7a5cff"
  // Base background colour.
  readonly property color background: Color.background
  // Default foreground colour.
  readonly property color foreground: Color.foreground
  // Urgent and attention colour.
  readonly property color urgent: Color.urgent
  // Semantic colors used by branding glyphs and lock overlays.
  readonly property color ceremony: Color.notifications.countdown
  // Attention color used by health status surfaces.
  readonly property color attention: Color.notifications.countdown
  // Base color used by the lock scrim.
  readonly property color lockOverlay: Color.lock.background
  // Shared surface border colour.
  readonly property color surfaceBorder: Color.tooltip.border
  // Shared panel corner radius.
  readonly property int cornerRadius: Style.cornerRadius
  // Shared panel border width: the host's panel frame width (KeyboardPanel, PopupCard, OSD).
  readonly property int borderWidth: Math.max(1, Style.space(2))
  // Shared panel padding.
  readonly property int panelPadding: Style.spacing.panelPadding
  // Shared row horizontal padding.
  readonly property int rowPadding: Style.spacing.rowPaddingX
  // Whether motion effects are enabled.
  readonly property bool motionEnabled: MotionState.motionEnabled
}
