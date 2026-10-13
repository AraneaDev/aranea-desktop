// Everyday system controls share the battery popup.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

RowLayout {
  id: tabs
  // Host-selected page.
  property string page: "power"
  // Offer Display when its controller loaded.
  property bool displayAvailable: false
  // Offer Health when its controller loaded.
  property bool healthAvailable: false
  // Live health severity used for the issue indicator.
  property string healthStatus: "healthy"
  // Open health issues shown on the prominent Health tab.
  property int problemCount: 0
  // Request a host-owned page change.
  signal pageRequested(string page)
  spacing: Style.space(8)
  Aranea.FilamentPill {
    objectName: "powerTab"
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Power"
    selected: tabs.page === "power"
    onClicked: tabs.pageRequested("power")
  }
  Aranea.FilamentPill {
    objectName: "displayTab"
    visible: tabs.displayAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Display"
    selected: tabs.page === "display"
    onClicked: tabs.pageRequested("display")
  }
  Aranea.FilamentPill {
    objectName: "healthTab"
    visible: tabs.healthAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Health" + (tabs.problemCount > 0 ? " · " + tabs.problemCount : "")
    selectedColor: tabs.healthStatus === "critical" ? Aranea.DesignTokens.urgent : tabs.healthStatus === "attention" ? Aranea.DesignTokens.attention : Aranea.DesignTokens.accent
    labelColor: tabs.problemCount > 0 ? selectedColor : selected ? Aranea.DesignTokens.foreground : Util.alpha(Aranea.DesignTokens.foreground, Aranea.DesignTokens.secondaryOpacity)
    selected: tabs.page === "health"
    onClicked: tabs.pageRequested("health")
  }
}
