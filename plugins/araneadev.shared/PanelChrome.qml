// Popup border policy shared by refined panel hosts.
pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  // Build popup chrome from the host's preferences; refined selects a neutral color.
  function popupBorder(refined: bool): var {
    // The host exposes popup colors dynamically.
    // qmllint disable missing-property
    var spec = Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
    if (refined) {
      spec.color = DesignTokens.surfaceBorder
      spec.gradient = {
        colors: [],
        angle: 0,
        enabled: false
      }
    }
    return spec
    // qmllint enable missing-property
  }
}
