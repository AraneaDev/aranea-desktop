// Sandbox NetworkManager boundary; production state mapping remains unchanged.
pragma Singleton
import QtQuick
import Quickshell.Networking as Native

QtObject {
  // The installed backend identity.
  property int backend: Native.NetworkBackendType.NetworkManager
  // Whether the backend can probe reachability.
  property bool canCheckConnectivity: true
  // Whether the operator permits connectivity checks.
  property bool connectivityCheckEnabled: true
  // The latest NM connectivity enum.
  property int connectivity: Native.NetworkConnectivity.Full
  // The fake radio state.
  property bool wifiEnabled: false
  // Plain snapshots of fake NM devices.
  property var devices: ({
      values: []
    })
  // Number of explicit probes requested.
  property int checks: 0
  // Record probes without touching networking.
  function checkConnectivity() {
    checks++
  }
}
