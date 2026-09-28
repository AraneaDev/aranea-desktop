// Shared Aranea component contract: visual primitives retain the host shell's
// border implementation while exposing the theme's common surface defaults.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.shared" as Shared
import qs.Commons

ShellRoot {
  QmlTest {
    id: t
  }

  Shared.SurfaceCard {
    id: card
    width: 120
    height: 80
    surface: "tooltip"
    borderColor: Color.tooltip.border
  }

  Shared.StatusRail {
    id: rail
    railColor: Color.accent
  }

  Shared.StatusTextPair {
    id: pair
    title: "TITLE"
    subtitle: "SUBTITLE"
    subtitleElide: Text.ElideRight
  }

  Component.onCompleted: {
    t.equal(card.radius, Style.cornerRadius, "surface cards use the shared corner radius")
    t.equal(card.borderWidth, 1, "surface cards keep a one-pixel border")
    t.equal(card.contentPadding, 0, "surface cards default to no content padding")
    t.equal(card.cornerRadius, Style.cornerRadius, "surface cards expose configurable corner radius")
    t.equal(rail.implicitWidth, Style.space(2), "status rails use the shared compact width")
    t.equal(pair.title, "TITLE", "status text pairs expose their title")
    t.equal(pair.subtitle, "SUBTITLE", "status text pairs expose their subtitle")
    t.done()
  }
}
