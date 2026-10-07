// Shared font drafts and preview samples with explicit owner-confirmed Apply.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "SettingsLogic.js" as Logic
import "../araneadev.shared" as Aranea

SettingsSection {
  id: section
  // Observed installed catalogs and persisted font families.
  property var fonts: ({})
  // Host mutation and inert-preview guards.
  property bool pending: false
  // Whether this section is an inert screenshot fixture.
  property bool displayOnly: false
  // Host pointer gate and latest application feedback.
  property var pointerGate: null
  // Latest owner-confirmed application outcome.
  property string result: ''
  // Latest actionable error for the font control.
  property string error: ''
  // Local drafts survive owner refreshes until discarded or acknowledged.
  property string uiDraft: ''
  // Locally selected monospace family; empty retains the default.
  property string technicalDraft: ''
  // Whether drafts must survive an incoming owner refresh.
  property bool dirty: false
  // Catalog and owner validation for the current draft.
  readonly property bool available: fonts.availability === 'available'
  // Whether the observed catalogs permit the current role choices.
  readonly property bool canApply: !!Logic.command('', 'configure fonts', [uiDraft, technicalDraft], {
    fonts: fonts
  })
  // Dispatch is owned by the persistent settings controller.
  signal request(string operation, var args)
  // Requests an owner read without applying drafts.
  signal retryRequested
  // Adopt observations only when they cannot overwrite a pending user choice.
  function syncDraft() {
    if (!dirty) {
      uiDraft = fonts.uiFamily || ''
      technicalDraft = fonts.technicalFamily || ''
    }
  }
  // Reset previews first; Apply remains the explicit persistence action.
  function resetDraft() {
    if (pending || displayOnly)
      return
    uiDraft = ''
    technicalDraft = ''
    dirty = true
  }
  // Send exact role choices after validation; never apply on selection.
  function applyFonts() {
    if (!pending && !displayOnly && canApply)
      request('configure fonts', [uiDraft, technicalDraft])
  }
  onFontsChanged: syncDraft()
  Component.onCompleted: syncDraft()
  title: 'Fonts'
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Used across Aranea panels and controls.'
    opacity: 0.65
  }
  GridLayout {
    Layout.fillWidth: true
    columns: width < Style.space(360) ? 1 : 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    FontSelector {
      Layout.fillWidth: true
      title: 'Interface font'
      families: section.fonts.families || []
      family: section.uiDraft
      enabled: section.available && !section.pending && !section.displayOnly
      pointerGate: section.pointerGate
      onChosen: function (family) {
        section.uiDraft = family
        section.dirty = true
      }
    }
    FontSelector {
      Layout.fillWidth: true
      title: 'Monospace font'
      families: section.fonts.monospaceFamilies || []
      family: section.technicalDraft
      enabled: section.available && !section.pending && !section.displayOnly
      pointerGate: section.pointerGate
      onChosen: function (family) {
        section.technicalDraft = family
        section.dirty = true
      }
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'The quick brown fox · Aranea desktop'
    font.family: section.uiDraft || Aranea.Typography.defaultUiFamily
    font.pixelSize: Style.font.body
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: '0123456789 · 2.667× · 3840 × 2160'
    font.family: section.technicalDraft || Aranea.Typography.defaultTechnicalFamily
    font.pixelSize: Style.font.body
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    SettingsButton {
      text: 'Apply'
      variant: 'primary'
      enabled: section.canApply && !section.pending && !section.displayOnly
      pointerGate: section.pointerGate
      onClicked: section.applyFonts()
    }
    SettingsButton {
      text: 'Reset to defaults'
      enabled: !section.pending && !section.displayOnly
      pointerGate: section.pointerGate
      onClicked: section.resetDraft()
    }
    SettingsButton {
      text: 'Retry'
      visible: !section.available
      enabled: !section.pending && !section.displayOnly
      pointerGate: section.pointerGate
      onClicked: section.retryRequested()
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!text
    text: section.error || section.result || (!section.available ? 'Font preferences unavailable. Retry, or reset and Apply to restore defaults.' : '')
    color: section.error ? Color.red : Color.foreground
    opacity: 0.8
  }
}
