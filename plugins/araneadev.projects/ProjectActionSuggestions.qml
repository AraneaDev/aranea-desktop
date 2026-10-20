// Detected commands offered as inert saves; running stays a separate explicit action.
pragma ComponentBehavior: Bound
// Host font tokens are runtime QObject properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "../araneadev.projects" as Projects
import "../araneadev.projects/ProjectActionSuggestions.js" as Suggestions
import "ProjectProblems.js" as Problems

ColumnLayout {
  id: section
  objectName: 'projectActionSuggestions'
  // Shared actions client owning detection and saves.
  property Projects.ProjectActionsClient client: null
  // Live saved definitions for the selected project.
  property var definitions: []
  // Capture boundary refuses every effect.
  property bool displayOnly: false
  // Shared pointer settling boundary.
  property var pointerGate: null
  // Collapsed once the project has saved actions; the user may expand it.
  property bool expanded: false
  // Unsaved suggestions according to live definitions; none until the snapshot is this project's.
  readonly property var rows: client && client.suggestionsReady ? Suggestions.pending(client.detection, definitions) : []
  // Rows grouped by source for presentation.
  readonly property var grouped: Suggestions.groups(rows)
  // How many rows Add all may save within the action limit.
  readonly property var plan: Suggestions.addPlan(rows, definitions.length)
  // Rows are listed when nothing is saved yet or the user expanded them.
  readonly property bool open: definitions.length === 0 || expanded
  // Sources that could not be checked.
  readonly property string note: client && client.detection ? Suggestions.sourceNote(client.detection.sources) : ''
  // Saves are refused while any mutation or Add all is in progress.
  readonly property bool busy: !client || displayOnly || client.pending || client.addActive
  // Open the editor with this draft; saving there follows the usual rules.
  signal editRequested(var definition)
  spacing: Style.space(8)
  // Once actions exist the section shows only unsaved rows; status lines are for an empty project.
  visible: !!client && client.suggestionsReady && (rows.length > 0 || definitions.length === 0 && (client.detecting || !!(client.detection && client.detection.error) || note !== ''))
  Aranea.UiLabel {
    objectName: 'suggestionsHeading'
    Layout.fillWidth: true
    visible: section.definitions.length === 0 && section.rows.length > 0
    text: 'Found in this repo'
    font.bold: true
  }
  Aranea.ActionButton {
    objectName: 'suggestionsToggle'
    visible: section.definitions.length > 0 && section.rows.length > 0
    text: 'Found in this repo · ' + section.rows.length + ' not added'
    variant: 'quiet'
    pointerGate: section.pointerGate
    onClicked: section.expanded = !section.expanded
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    visible: !!section.client && section.client.detecting && section.rows.length === 0
    text: 'Looking for commands…'
    opacity: 0.65
  }
  RowLayout {
    Layout.fillWidth: true
    visible: !!section.client && !!section.client.detection && !!section.client.detection.error
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: "Couldn't look for commands."
      color: Aranea.DesignTokens.attention
    }
    Aranea.ActionButton {
      objectName: 'suggestionsRetry'
      text: 'Retry'
      enabled: !section.displayOnly
      pointerGate: section.pointerGate
      onClicked: section.client.detect(true)
    }
  }
  Repeater {
    model: section.open ? section.grouped : []
    ColumnLayout {
      id: group
      required property var modelData
      Layout.fillWidth: true
      spacing: Style.space(6)
      Aranea.UiLabel {
        Layout.fillWidth: true
        visible: section.grouped.length > 1
        text: group.modelData.title
        technical: true
        opacity: 0.8
      }
      Repeater {
        model: group.modelData.rows
        ColumnLayout {
          id: suggestion
          required property var modelData
          Layout.fillWidth: true
          spacing: Style.space(2)
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: suggestion.modelData.definition.name + ' · ' + (suggestion.modelData.definition.kind === 'service' ? 'Service' : 'Command')
            font.bold: true
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
          }
          Aranea.UiLabel {
            Layout.fillWidth: true
            text: Suggestions.sourceLine(suggestion.modelData)
            technical: true
            opacity: 0.65
            wrapMode: Text.WrapAnywhere
          }
          Aranea.UiLabel {
            Layout.fillWidth: true
            visible: text !== ''
            text: Suggestions.previewLine(suggestion.modelData)
            technical: true
            opacity: 0.65
          }
          Flow {
            Layout.fillWidth: true
            spacing: Style.space(8)
            Aranea.ActionButton {
              objectName: 'suggestionAdd:' + suggestion.modelData.key
              text: 'Add'
              enabled: !section.busy && section.plan.capacity > 0
              pointerGate: section.pointerGate
              onClicked: section.client.addSuggestions([suggestion.modelData.definition])
            }
            Aranea.ActionButton {
              objectName: 'suggestionEdit:' + suggestion.modelData.key
              text: 'Edit'
              variant: 'quiet'
              enabled: !section.busy
              pointerGate: section.pointerGate
              onClicked: section.editRequested(suggestion.modelData.definition)
            }
          }
        }
      }
    }
  }
  Aranea.ActionButton {
    objectName: 'suggestionsAddAll'
    visible: section.open && section.rows.length > 1
    text: section.plan.limited ? 'Add first ' + section.plan.capacity : 'Add all'
    enabled: !section.busy && section.plan.capacity > 0
    pointerGate: section.pointerGate
    onClicked: section.client.addSuggestions(section.plan.rows.map(function (row) {
      return row.definition
    }))
  }
  Aranea.UiLabel {
    objectName: 'suggestionsLimit'
    Layout.fillWidth: true
    visible: section.open && section.plan.limited
    text: 'A project can save up to 50 actions; ' + (section.rows.length - section.plan.capacity) + ' more would exceed it.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    opacity: 0.65
  }
  Aranea.UiLabel {
    objectName: 'suggestionsResult'
    Layout.fillWidth: true
    visible: !!section.client && !!section.client.addResult && (section.client.addResult.total > 1 || !!section.client.addResult.error || section.client.addResult.cancelled)
    text: !section.client || !section.client.addResult ? '' : section.client.addResult.error ? 'Added ' + section.client.addResult.added + ' of ' + section.client.addResult.total + '. Nothing else was changed.' : section.client.addResult.cancelled ? 'Added ' + section.client.addResult.added + ' of ' + section.client.addResult.total + ' · Stopped; the rest were not saved.' : 'Added ' + section.client.addResult.added + ' actions.'
    color: section.client && section.client.addResult && section.client.addResult.error ? Aranea.DesignTokens.attention : Aranea.DesignTokens.foreground
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Projects.ProjectProblem {
    objectName: 'suggestionsProblem'
    Layout.fillWidth: true
    displayOnly: section.displayOnly
    pointerGate: section.pointerGate
    problem: section.client && section.client.addResult && section.client.addResult.error ? Problems.problem(section.client.addResult.error, {
      surface: 'suggestions',
      actions: []
    }) : null
  }
  Aranea.UiLabel {
    objectName: 'suggestionsNote'
    Layout.fillWidth: true
    visible: section.note !== ''
    text: section.note
    opacity: 0.65
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
}
