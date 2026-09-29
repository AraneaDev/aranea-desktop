// Shared projections of runtime directories used by Aranea plugins.
// Keeping these paths here prevents plugin-local copies from drifting apart.
pragma Singleton

import QtQuick
import Quickshell

QtObject {
  // The user's home directory.
  readonly property string home: Quickshell.env("HOME")

  // XDG state storage, with the conventional fallback when unset.
  readonly property string xdgStateHome: Quickshell.env("XDG_STATE_HOME") || (home + "/.local/state")

  // Aranea's persistent state directory.
  readonly property string araneaStateRoot: xdgStateHome + "/aranea"

  // Omarchy's persistent state directory.
  readonly property string omarchyStateRoot: xdgStateHome + "/omarchy"

  // The configured Omarchy installation path.
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // Root directory for the active theme's branding assets.
  readonly property string themeRoot: omarchyStateRoot + "/current/theme"
  readonly property string brandingRoot: themeRoot + "/branding"

  // Directory containing branding marks.
  readonly property string brandingMarksPath: brandingRoot + "/marks/"

  // Directory containing branding motifs.
  readonly property string brandingMotifsPath: brandingRoot + "/motifs/"

  // Directory containing branding glyphs.
  readonly property string brandingGlyphsPath: brandingRoot + "/glyphs/"

  // File URL for the primary Aranea branding glyph.
  readonly property string glyphUrl: "file://" + brandingMarksPath + "aranea-glyph.svg"

  // File storing the shared reduced-motion preference.
  readonly property string motionStatePath: araneaStateRoot + "/motion"

  // Persistent emoji recents owned by the Aranea picker.
  readonly property string emojiRecentsPath: araneaStateRoot + "/emoji-recent.json"

  // Omarchy's reboot-required marker consumed by the updates widget.
  readonly property string rebootRequiredPath: omarchyStateRoot + "/reboot-required"
}
