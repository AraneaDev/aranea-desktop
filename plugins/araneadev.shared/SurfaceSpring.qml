// Shared restrained spring for spatial and scale transitions.
import QtQuick

SpringAnimation {
  spring: DesignTokens.springStrength
  damping: DesignTokens.springDamping
  mass: 1.0
  epsilon: 0.25
}
