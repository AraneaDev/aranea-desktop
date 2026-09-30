// A Text whose glyph ink, not its advance width, sits on the alignment line:
// AlignHCenter centres the ink, AlignLeft starts the ink at x, AlignRight ends
// the ink at the right edge. For icon glyphs (Nerd Font advance widths carry
// side bearings) and for trailing values that must meet a content edge.
// qmllint disable missing-property
import QtQuick

Text {
  id: ink

  // Ink box of the text relative to its origin and baseline (TextMetrics).
  readonly property rect inkRect: metrics.tightBoundingRect
  // Horizontal shift applied so the ink meets the alignment line.
  readonly property real inkShift: ink.horizontalAlignment === Text.AlignHCenter ? metrics.advanceWidth / 2 - (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width / 2) : (ink.horizontalAlignment === Text.AlignRight ? metrics.advanceWidth - (metrics.tightBoundingRect.x + metrics.tightBoundingRect.width) : -metrics.tightBoundingRect.x)

  textFormat: Text.PlainText

  TextMetrics {
    id: metrics
    font: ink.font
    text: ink.text
  }

  transform: Translate {
    x: ink.inkShift
  }
}
