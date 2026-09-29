// Shared reduced-motion preference for Aranea UI components.
// The environment override wins over the persisted preference.
pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: motion

  // Whether animations are currently allowed.
  property bool motionEnabled: reducedByEnvironment ? false : true

  // Whether the process environment requests reduced motion.
  readonly property bool reducedByEnvironment: Quickshell.env("ARANEA_REDUCED_MOTION") === "1"

  // The shared persisted preference path.
  readonly property string statePath: RuntimePaths.motionStatePath

  FileView {
    path: motion.statePath
    watchChanges: true
    printErrors: false
    onLoaded: motion.motionEnabled = !motion.reducedByEnvironment && String(text() || "").trim() !== "off"
    onLoadFailed: motion.motionEnabled = !motion.reducedByEnvironment
    onFileChanged: reload()
  }
}
