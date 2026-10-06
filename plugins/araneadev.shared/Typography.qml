// Shared font roles: watched user preferences, technical values and icon glyphs.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import Quickshell.Io
import qs.Commons

Item {
  id: typography
  // Valid font preferences, with empty families retaining the desktop defaults.
  property var preferences: ({})
  // Interface text follows the user's choice, then the desktop default.
  readonly property string uiFamily: preferences.uiFamily || "sans-serif"
  // Technical values use the user's monospace choice, then the desktop alias.
  readonly property string technicalFamily: preferences.technicalFamily || Style.font.family
  // Icon glyphs always retain the host's dedicated Nerd Font alias.
  readonly property string iconFamily: Style.font.family
  // Reject malformed file contents without disrupting text rendering.
  function readPreferences(contents) {
    try {
      var parsed = JSON.parse(contents)
      preferences = parsed && typeof parsed.uiFamily === "string" && typeof parsed.technicalFamily === "string" ? parsed : ({})
    } catch (error) {
      preferences = ({})
    }
  }
  // Explicit owner readback also covers creation of a previously absent file.
  function refresh() {
    fontFile.reload()
  }
  FileView {
    id: fontFile
    path: RuntimePaths.fontsConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: typography.readPreferences(text())
    onLoadFailed: typography.preferences = ({})
    onFileChanged: reload()
  }
}
