// What an agent changed in a task checkout, with the next steps; shown when the work is ready for review.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea
import "ProjectOverview.js" as Overview
import "ProjectProblems.js" as Problems
import "ProjectReview.js" as Review

ProjectSectionCard {
  id: card
  objectName: 'projectReviewCard'
  // Plain model from the surface: {branch, data, error, agentReport, checksText, hasChecks,
  // canRunChecks, canOpenDiff, pushPending, pushBlocked, markPending, problem}.
  property var review: ({})
  // Capture boundary refuses every external action.
  property bool displayOnly: false
  // Shared pointer settlement gate for moving content.
  property var pointerGate: null
  // Every commit subject is listed, not just the first five.
  property bool showAll: false
  // Review data from the helper, or null before it was read.
  readonly property var info: review.data || null
  // Commit subjects, newest first.
  readonly property var commits: info ? info.commits || [] : []
  // Commit rows currently listed.
  readonly property var shown: showAll ? commits : commits.slice(0, 5)
  // Plain commits and files line.
  readonly property string changesText: Review.changesLine(info)
  // Changed files, first five unless Show all is on.
  readonly property var files: info ? info.files || [] : []
  // File rows currently listed.
  readonly property var shownFiles: showAll ? files : files.slice(0, 5)
  // Run checks was pressed.
  signal runChecksRequested
  // Open diff was pressed.
  signal openDiffRequested
  // Push branch was pressed.
  signal pushRequested
  // Mark reviewed was pressed.
  signal markRequested
  // Remove task checkout was pressed.
  signal removeRequested
  Aranea.UiLabel {
    objectName: 'reviewTitle'
    Layout.fillWidth: true
    text: 'Ready for review · ' + (card.review.branch || '')
    font.bold: true
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'reviewTask'
    Layout.fillWidth: true
    visible: text !== ''
    text: card.review.taskSummary || ''
    elide: Text.ElideRight
    maximumLineCount: 2
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'reviewFinished'
    Layout.fillWidth: true
    visible: typeof card.review.taskFinishedAt === 'number'
    text: typeof card.review.taskFinishedAt === 'number' ? 'Finished ' + Overview.ageLabel(card.review.taskFinishedAt, Date.now()) : ''
    opacity: 0.7
  }
  Aranea.UiLabel {
    objectName: 'reviewSummary'
    Layout.fillWidth: true
    visible: !!card.info
    text: card.info ? 'Compared with ' + card.info.base + (card.info.behind > 0 ? ' · ' + card.info.behind + ' behind it' : '') : ''
    opacity: 0.7
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Aranea.UiLabel {
    objectName: 'reviewChanges'
    Layout.fillWidth: true
    visible: !!card.info
    text: card.changesText
  }
  Repeater {
    model: card.shown
    Aranea.UiLabel {
      id: commit
      required property var modelData
      required property int index
      objectName: 'reviewCommit:' + index
      Layout.fillWidth: true
      text: commit.modelData.subject
      elide: Text.ElideRight
      opacity: 0.85
    }
  }
  Repeater {
    model: card.shownFiles
    Aranea.UiLabel {
      id: file
      required property var modelData
      required property int index
      objectName: 'reviewFile:' + index
      Layout.fillWidth: true
      text: file.modelData.path + '  ' + (typeof file.modelData.added === 'number' && typeof file.modelData.removed === 'number' ? '+' + file.modelData.added + ' -' + file.modelData.removed : 'binary')
      elide: Text.ElideMiddle
      opacity: 0.85
    }
  }
  Aranea.ActionButton {
    objectName: 'reviewShowAll'
    visible: card.commits.length > 5 || card.files.length > 5
    text: card.showAll ? 'Show fewer' : 'Show all'
    variant: 'quiet'
    pointerGate: card.pointerGate
    onClicked: card.showAll = !card.showAll
  }
  Aranea.UiLabel {
    objectName: 'reviewUncommitted'
    Layout.fillWidth: true
    visible: !!card.info && !!card.info.uncommitted && (card.info.uncommitted.dirty || card.info.uncommitted.untracked)
    text: 'Uncommitted changes'
    color: Aranea.DesignTokens.attention
  }
  Aranea.UiLabel {
    objectName: 'reviewAgentReport'
    Layout.fillWidth: true
    text: 'Agent reported: ' + (card.review.agentReport || 'not reported')
  }
  Aranea.UiLabel {
    objectName: 'reviewChecks'
    Layout.fillWidth: true
    text: 'Your checks: ' + (card.review.checksText || 'not run')
  }
  ProjectProblem {
    objectName: 'reviewProblem'
    Layout.fillWidth: true
    displayOnly: card.displayOnly
    pointerGate: card.pointerGate
    problem: card.review.error ? Problems.problem(card.review.error, {
      surface: 'review',
      actions: []
    }) : null
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Aranea.ActionButton {
      objectName: 'reviewRunChecks'
      visible: !!card.review.hasChecks
      text: 'Run checks'
      enabled: !card.displayOnly && !!card.review.canRunChecks
      pointerGate: card.pointerGate
      onClicked: card.runChecksRequested()
    }
    Aranea.ActionButton {
      objectName: 'reviewOpenDiff'
      text: 'Open diff'
      enabled: !card.displayOnly && !!card.review.canOpenDiff
      pointerGate: card.pointerGate
      onClicked: card.openDiffRequested()
    }
    Aranea.ActionButton {
      objectName: 'reviewPush'
      text: card.review.pushPending ? 'Pushing…' : 'Push branch'
      enabled: !card.displayOnly && !card.review.pushBlocked
      pointerGate: card.pointerGate
      onClicked: card.pushRequested()
    }
    Aranea.ActionButton {
      objectName: 'reviewMark'
      text: 'Mark reviewed'
      enabled: !card.displayOnly && !!card.info && !card.review.markPending && !card.review.readError
      pointerGate: card.pointerGate
      onClicked: card.markRequested()
    }
    Aranea.ActionButton {
      objectName: 'reviewRemove'
      text: 'Remove task checkout'
      variant: 'quiet'
      enabled: !card.displayOnly && !card.review.pushBlocked
      pointerGate: card.pointerGate
      onClicked: card.removeRequested()
    }
  }
}
