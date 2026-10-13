// Connectivity pages share one popup; the host owns page selection.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

RowLayout {
  id: tabs
  // Host-owned current page.
  property string page: "network"
  // Only offer tunnels when the optional VPN controller loaded.
  property bool vpnAvailable: false
  // Only offer Bluetooth when its optional controller loaded.
  property bool bluetoothAvailable: false
  // Number of connected tunnels shown beside VPN.
  property int connectedCount: 0
  // Request a page change without changing any network connection.
  signal pageRequested(string page)
  visible: vpnAvailable || bluetoothAvailable
  spacing: Style.space(8)
  Aranea.FilamentPill {
    objectName: "networkTab"
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Network"
    selected: tabs.page === "network"
    onClicked: tabs.pageRequested("network")
  }
  Aranea.FilamentPill {
    objectName: "vpnTab"
    visible: tabs.vpnAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "VPN" + (tabs.connectedCount > 0 ? " · " + tabs.connectedCount : "")
    selected: tabs.page === "vpn"
    onClicked: tabs.pageRequested("vpn")
  }
  Aranea.FilamentPill {
    objectName: "bluetoothTab"
    visible: tabs.bluetoothAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Bluetooth"
    selected: tabs.page === "bluetooth"
    onClicked: tabs.pageRequested("bluetooth")
  }
}
