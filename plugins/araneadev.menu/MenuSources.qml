// JSONC menu sources of the Aranea menu (MenuSources): Omarchy's default menu
// file and the user's extension, watched so live edits apply without a shell
// restart. Menu.qml owns one and pulls the merged items with merge().
import Quickshell
import Quickshell.Io
import QtQuick
import "MenuModel.js" as MenuModel

Item {
  id: sources

  // Omarchy's install path (the default menu file lives under it).
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Omarchy's default menu file.
  property string defaultMenuPath: sources.omarchyPath + "/default/omarchy/omarchy-menu.jsonc"
  // User extension file merged over the defaults.
  property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"
  // Installed settings manifest; fixtures may point this at a scratch plugin.
  property string settingsManifestPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/araneadev.settings/manifest.json"
  // Optional manifest has reported, including a missing or malformed file.
  property bool settingsManifestSeen: false
  // Whether the optional settings destination is installed.
  property bool settingsAvailable: false
  onSettingsAvailableChanged: updated()
  // Watched installed manifest for the standalone Projects component.
  property string projectsManifestPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/araneadev.projects/manifest.json"
  // Availability of the independently installed Projects destination.
  property bool projectsAvailable: false
  onProjectsAvailableChanged: updated()
  // Items parsed from the default file.
  property var defaultMenuItems: []
  // Items parsed from the user file ([] when it is missing).
  property var userMenuItems: []
  // The default file has loaded (or is missing).
  property bool defaultMenuSeen: false
  // The user file has loaded (or is missing).
  property bool userMenuSeen: false
  // All three sources have reported: a pending route can only resolve then.
  readonly property bool ready: sources.defaultMenuSeen && sources.userMenuSeen && sources.settingsManifestSeen

  // Emitted whenever a file loaded, failed to load or changed.
  signal updated

  // Merges the user file over the defaults ({items, itemOrder}); later keys win per item.
  function merge(): var {
    return MenuModel.mergeMenuSources(sources.defaultMenuItems, sources.userMenuItems, sources.settingsAvailable, sources.projectsAvailable)
  }

  // Reads all menu sources and optional plugin availability again.
  function reload(): void {
    settingsManifestFile.reload()
    projectsManifestFile.reload()
    defaultMenuFile.reload()
    userMenuFile.reload()
  }

  // The JSONC sources are watched so live edits to the default file (or the
  // user extension at ~/.config/omarchy/extensions/omarchy-menu.jsonc) take
  // effect without restarting the shell.
  FileView {
    id: projectsManifestFile
    path: sources.projectsManifestPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        sources.projectsAvailable = JSON.parse(text()).id === "araneadev.projects"
      } catch (e) {
        sources.projectsAvailable = false
      }
      sources.updated()
    }
    onLoadFailed: {
      sources.projectsAvailable = false
      sources.updated()
    }
    onFileChanged: reload()
  }

  FileView {
    id: settingsManifestFile
    path: sources.settingsManifestPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      try {
        sources.settingsAvailable = JSON.parse(text()).id === "araneadev.settings"
      } catch (e) {
        sources.settingsAvailable = false
      }
      sources.settingsManifestSeen = true
      sources.updated()
    }
    onLoadFailed: {
      sources.settingsAvailable = false
      sources.settingsManifestSeen = true
      sources.updated()
    }
    onFileChanged: reload()
  }

  FileView {
    id: defaultMenuFile
    path: sources.defaultMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      sources.defaultMenuItems = MenuModel.parseMenuJsonc(text())
      sources.defaultMenuSeen = true
      sources.updated()
    }
    onLoadFailed: {
      sources.defaultMenuSeen = true
      sources.updated()
    }
    onFileChanged: reload()
  }

  FileView {
    id: userMenuFile
    path: sources.userMenuPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      sources.userMenuItems = MenuModel.parseMenuJsonc(text())
      sources.userMenuSeen = true
      sources.updated()
    }
    onLoadFailed: {
      sources.userMenuItems = []
      sources.userMenuSeen = true
      sources.updated()
    }
    onFileChanged: reload()
  }
}
