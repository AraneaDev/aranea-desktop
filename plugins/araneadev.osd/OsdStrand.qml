// The OSD's level strand (Osd.qml): a hairline track whose lit part runs
// the Filament strand gradient, mint to violet, as FilamentBar's and
// FilamentSlider's lit strands do, with the OSD's own accent knob at the
// level. Without progress (a message OSD) a short fixed stub is lit. Pure
// view: a fraction in, nothing out.
import QtQuick
import qs.Commons
import "../araneadev.shared" as Aranea

Item {
  id: strand

  // Lit part of the track, 0..1 (OsdModel.progressFraction).
  property real fraction: 0
  // Whether a level is shown; false lights the fixed stub instead.
  property bool hasProgress: true
  // Animate the fill and knob as the level moves.
  property bool motionEnabled: true
  // Lit fraction actually drawn: the level, or the stub without progress.
  readonly property real litFraction: strand.hasProgress ? strand.fraction : 0.28

  Rectangle {
    objectName: "osdStrandTrack"
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Color.popups.text, 0.3)
  }
  Rectangle {
    objectName: "osdStrandFill"
    width: strand.width * strand.litFraction
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    height: Math.max(2, Style.spacing.sm)
    radius: height / 2
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop {
        position: 0
        color: Aranea.DesignTokens.accent
      }
      GradientStop {
        position: 1
        color: Aranea.DesignTokens.strandEnd
      }
    }
    Behavior on width {
      enabled: strand.motionEnabled
      NumberAnimation {
        duration: 140
        easing.type: Easing.OutCubic
      }
    }
  }
  Rectangle {
    objectName: "osdStrandKnob"
    width: Style.space(8)
    height: width
    radius: width / 2
    x: strand.width * strand.litFraction - width / 2
    anchors.verticalCenter: parent.verticalCenter
    color: Aranea.DesignTokens.accent
    Behavior on x {
      enabled: strand.motionEnabled
      NumberAnimation {
        duration: 140
        easing.type: Easing.OutCubic
      }
    }
  }
}
