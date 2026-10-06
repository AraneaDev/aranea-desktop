// Surface border policy shared by refined first-party hosts.
// qmllint disable missing-property
pragma Singleton
import QtQuick
import qs.Commons

QtObject {
  // Build popup chrome from the host's preferences; refined selects a neutral color.
  function popupBorder(refined: bool): var {
    return surfaceBorder("popups", "border", Color.popups.border, Math.max(1, Style.space(2)), refined)
  }
  // Neutral presentation keeps the requested surface edge widths intact.
  function surfaceBorder(surface: string, prefix: string, fallbackColor: color, fallbackWidth: real, refined: bool): var {
    // The host exposes popup colors dynamically.
    // qmllint disable missing-property
    var spec = Border.surfaceSpec(surface, prefix, fallbackColor, fallbackWidth, "border-alpha")
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
