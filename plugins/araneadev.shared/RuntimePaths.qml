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

  // XDG config storage, with the conventional fallback when unset.
  readonly property string xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME") || (home + "/.config")

  // Aranea's user-owned config directory.
  readonly property string araneaConfigRoot: xdgConfigHome + "/aranea"

  // The optional own-app VPNs file read by araneadev.vpn (user-owned; the
  // theme never writes it).
  readonly property string vpnAppsPath: araneaConfigRoot + "/vpn-apps.json"

  // Aranea's persistent state directory.
  readonly property string araneaStateRoot: Quickshell.env("ARANEA_STATE_ROOT") || (xdgStateHome + "/aranea")

  // Versioned development-project registry shared with the CLI.
  readonly property string projectsRegistryPath: araneaStateRoot + "/projects.json"

  // Omarchy's persistent state directory.
  readonly property string omarchyStateRoot: xdgStateHome + "/omarchy"

  // The configured Omarchy installation path.
  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")

  // Root directory for the active theme's branding assets.
  readonly property string themeRoot: omarchyStateRoot + "/current/theme"

  // Root directory for branding assets within the active theme.
  readonly property string brandingRoot: themeRoot + "/branding"

  // Directory containing branding marks.
  readonly property string brandingMarksPath: brandingRoot + "/marks/"

  // Directory containing branding motifs.
  readonly property string brandingMotifsPath: brandingRoot + "/motifs/"

  // Directory containing branding glyphs.
  readonly property string brandingGlyphsPath: brandingRoot + "/glyphs/"

  // File URL for the canonical branding mark.
  readonly property string brandUrl: "file://" + brandingRoot + "/" + BrandConfig.markFile

  // Compatibility alias for components that still call this a glyph.
  readonly property string glyphUrl: brandUrl

  // User-owned shared interface and technical font preferences.
  readonly property string fontsConfigPath: araneaConfigRoot + "/fonts.json"

  // File storing the shared reduced-motion preference.
  readonly property string motionStatePath: araneaStateRoot + "/motion"

  // Persistent emoji recents owned by the Aranea picker.
  readonly property string emojiRecentsPath: araneaStateRoot + "/emoji-recent.json"

  // Omarchy's reboot-required marker consumed by the updates widget.
  readonly property string rebootRequiredPath: omarchyStateRoot + "/reboot-required"
}
