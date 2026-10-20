// Weather preferences stay reachable when its standalone bar slot is consolidated.
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

Column {
  id: preferences
  // Explicit unit override; empty follows the resolved location and locale.
  property string unit: ""
  // Match the native weather model's case/whitespace handling and auto fallback.
  readonly property string normalizedUnit: unit.trim().toLowerCase()
  // Current persisted refresh period, including a custom existing value.
  property int refreshMinutes: 15
  // Owner's keyboard catcher, restored only while this page is still visible.
  property var focusTarget: null
  // Numeric editing temporarily owns the shared panel's keys.
  readonly property bool editing: minuteInput.activeFocus
  // Invalid input stays local and never changes the saved configuration.
  property string validationMessage: ""
  // Runtime font tokens are supplied by the native shell.
  readonly property var fontSizes: Style.font
  // Patch only the selected preference; the owner merges other settings.
  signal settingsRequested(var values)

  // Discard unsubmitted numeric text after dismissal or an outside focus change.
  function resetRefresh() {
    minuteInput.text = String(refreshMinutes)
    validationMessage = ""
  }
  // Return focus without allowing a queued callback to steal another page's keys.
  function releaseEditor() {
    minuteInput.focus = false
    Qt.callLater(function () {
      if (preferences.visible && preferences.focusTarget)
        preferences.focusTarget.forceActiveFocus()
    })
  }
  // Accept whole minutes from one minute through one day; reject partial numbers.
  function commitRefresh() {
    var raw = minuteInput.text.trim()
    var value = Number(raw)
    if (!/^\d+$/.test(raw) || value < 1 || value > 1440) {
      validationMessage = "Enter 1–1440 minutes"
      return
    }
    validationMessage = ""
    settingsRequested({
      refreshMinutes: value
    })
    releaseEditor()
  }

  spacing: Style.space(8)
  onRefreshMinutesChanged: if (!editing)
    resetRefresh()
  onVisibleChanged: if (!visible) {
    resetRefresh()
    minuteInput.focus = false
  }
  Component.onCompleted: resetRefresh()

  RowLayout {
    width: parent.width
    spacing: Style.space(8)
    Aranea.UiLabel {
      text: "Units"
      Layout.fillWidth: true
    }
    Aranea.FilamentPill {
      objectName: "automaticUnits"
      text: "Auto"
      selected: preferences.normalizedUnit !== "metric" && preferences.normalizedUnit !== "imperial"
      onClicked: preferences.settingsRequested({
        unit: ""
      })
    }
    Aranea.FilamentPill {
      objectName: "metricUnits"
      text: "Metric"
      selected: preferences.normalizedUnit === "metric"
      onClicked: preferences.settingsRequested({
        unit: "metric"
      })
    }
    Aranea.FilamentPill {
      objectName: "imperialUnits"
      text: "Imperial"
      selected: preferences.normalizedUnit === "imperial"
      onClicked: preferences.settingsRequested({
        unit: "imperial"
      })
    }
  }
  RowLayout {
    width: parent.width
    spacing: Style.space(8)
    Aranea.UiLabel {
      text: "Refresh · minutes"
      Layout.fillWidth: true
    }
    Rectangle {
      Layout.preferredWidth: Style.space(60)
      Layout.preferredHeight: Style.space(28)
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.04)
      border.width: 1
      border.color: Util.alpha(Aranea.DesignTokens.foreground, 0.16)
      TextInput {
        id: minuteInput
        objectName: "refreshMinutes"
        anchors.fill: parent
        anchors.margins: Style.space(5)
        text: String(preferences.refreshMinutes)
        color: Aranea.DesignTokens.foreground
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: preferences.fontSizes.body
        selectByMouse: true
        clip: true
        maximumLength: 10
        onActiveFocusChanged: if (!activeFocus)
          preferences.resetRefresh()
        Keys.onReturnPressed: preferences.commitRefresh()
        Keys.onEnterPressed: preferences.commitRefresh()
        Keys.onEscapePressed: {
          preferences.resetRefresh()
          preferences.releaseEditor()
        }
      }
    }
    Aranea.FilamentPill {
      objectName: "applyRefresh"
      text: "Apply"
      onClicked: preferences.commitRefresh()
    }
  }
  Aranea.UiLabel {
    visible: preferences.validationMessage.length > 0
    text: preferences.validationMessage
    color: Aranea.DesignTokens.attention
  }
}
