// External SNI records only. Production delegates and effects render unchanged.
pragma Singleton
import QtQuick
import Quickshell

QtObject {
  // Three native item records: dark, light and color rendering cases.
  property var items: ({
      values: [record("dark-symbolic"), record("light-symbolic"), record("color")]
    })
  // Build an external SNI record pointing to a private fixture image.
  function record(name) {
    return {
      id: name,
      title: name,
      icon: "file://" + Quickshell.env("ARANEA_NATIVE_CAPTURE") + "/" + name,
      status: 1,
      onlyMenu: false,
      tooltipTitle: name
    }
  }
}
