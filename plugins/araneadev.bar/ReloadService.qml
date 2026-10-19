// A keepLoaded companion service survives stock Omarchy's bar/widget remounts.
import QtQuick
import Quickshell
import "../araneadev.shared" as Aranea

Item {
  id: service
  // Host injection confirms this is the selected bar's installed service.
  property var shell: null
  Aranea.PluginReloadController {
    active: service.shell !== null && Quickshell.shellDir === Aranea.RuntimePaths.omarchyPath + '/shell'
  }
}
