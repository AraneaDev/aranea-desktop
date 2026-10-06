// Shared font roles for proportional controls, technical content and icon glyphs.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import Quickshell
import qs.Commons

QtObject {
  // UI labels preserve an explicit menu font override, then use the system UI alias.
  readonly property string uiFamily: Quickshell.env("OMARCHY_MENU_FONT") || "sans-serif"
  // Technical values follow the desktop monospace alias.
  readonly property string technicalFamily: Style.font.family
  // Nerd Font glyphs stay independent from proportional labels.
  readonly property string iconFamily: Style.font.family
}
