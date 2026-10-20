// Calendar, World Clock and Weather share the clock's keyboard popup.
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

RowLayout {
  id: tabs
  // Selected host-owned section.
  property string page: "calendar"
  // Optional page availability follows successful controller construction.
  property bool worldClockAvailable: false
  // Weather is offered only when its controller loaded.
  property bool weatherAvailable: false
  // Requests a page change without claiming another popout.
  signal pageRequested(string page)
  spacing: Style.space(8)
  Aranea.FilamentPill {
    objectName: "calendarTab"
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Calendar"
    selected: tabs.page === "calendar"
    onClicked: tabs.pageRequested("calendar")
  }
  Aranea.FilamentPill {
    objectName: "worldClockTab"
    visible: tabs.worldClockAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "World Clock"
    selected: tabs.page === "worldclock"
    onClicked: tabs.pageRequested("worldclock")
  }
  Aranea.FilamentPill {
    objectName: "weatherTab"
    visible: tabs.weatherAvailable
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    text: "Weather"
    selected: tabs.page === "weather"
    onClicked: tabs.pageRequested("weather")
  }
}
