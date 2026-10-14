// Selected project identity and its primary action stay separate from settings.
// qmllint disable missing-property
pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs.Commons
import "../araneadev.shared" as Aranea
import "ProjectProfiles.js" as Profiles

ColumnLayout {
  id: header
  objectName: 'projectHeader'
  // Narrow hosts reach the full project picker from the selected header.
  property bool compact: false
  // Host draft guards prevent changing the checkout underneath an editor.
  property bool navigationEnabled: true
  // Project inspection and checkout switching never submit Open.
  signal projectPickerRequested
  // Select an exact registered checkout without launching tools.
  signal checkoutRequested(string projectId, string checkoutId)
  // Current saved project identity; this view never changes registration.
  property var project: null
  // Exact selected Git observation overrides registry branch labels only for its pair.
  property var git: null
  // Cached branch observations remain explicitly marked when old or failed.
  property bool gitStale: false
  // Branch identity comes from Git when available; registry metadata is labelled.
  readonly property string branchText: {
    if (!checkout)
      return 'None'
    if (git && project && git.projectId === project.id && git.checkoutId === checkout.id)
      return (git.detached ? 'detached HEAD' : git.branch || 'unavailable') + (gitStale ? ' (last observed)' : '')
    return (checkout.branch || 'detached') + ' (registered)'
  }
  // Submission state only; accepted native work continues independently.
  property bool openAvailable: false
  // Disable rapid duplicate submission while the owner is preparing.
  property bool pending: false
  // A held acknowledgement is uncertainty, not active preparation.
  property bool acceptanceUnknown: false
  // The current management destination already supplies its own heading.
  property bool managementActive: false
  // Inert capture refuses launch and registry effects.
  property bool displayOnly: false
  // Shared content-settlement pointer guard.
  property var pointerGate: null
  // Current supported adapter probe supplies readable actual tool labels.
  property var tools: ({})
  // Optional unclipped parent for searchable popups.
  property Item menuHost: null
  // Resolve only the registered current selection.
  readonly property var checkout: project ? (project.checkouts || []).find(function (c) {
    return c.id === header.project.lastCheckoutId
  }) || null : null
  // Use the remembered accepted profile without selecting a substitute.
  readonly property var profile: Profiles.remembered(project)
  // Readable actual adapters or one actionable missing-tool explanation.
  readonly property string profileSummary: profile ? Profiles.summary(profile, tools) : 'Choose a profile to start working.'
  // Explicit saved profile identity and revision for the current checkout.
  signal startProfile(string profileId, int profileRevision)
  // Navigate to optional profile management without launching.
  signal manageProfilesRequested
  // Resolve again at activation so removed profiles cannot be started from stale rows.
  function chooseProfile(id) {
    if (!project || displayOnly || pending || acceptanceUnknown || !openAvailable)
      return
    var selected = (project.profiles || []).find(function (p) {
      return p.id === id
    })
    if (selected)
      startProfile(selected.id, selected.revision)
  }
  ProjectPicker {
    id: profilePicker
    objectName: 'profilePicker'
    showCheckoutContext: false
    searchPlaceholder: 'Search profiles…'
    parent: header.menuHost || header
    rows: header.project ? (header.project.profiles || []).map(function (p) {
      return {
        id: p.id,
        name: p.name,
        path: Profiles.summary(p, header.tools)
      }
    }) : []
    selectedId: header.profile ? header.profile.id : ''
    displayOnly: header.displayOnly || header.pending || header.acceptanceUnknown || !header.openAvailable
    pointerGate: header.pointerGate
    onSelected: function (id) {
      header.chooseProfile(id)
    }
  }
  ProjectPicker {
    id: checkoutPicker
    objectName: 'checkoutPicker'
    parent: header.menuHost || header
    rows: header.project ? (header.project.checkouts || []).map(function (checkout) {
      return {
        id: checkout.id,
        name: checkout.branch || 'detached',
        branch: checkout.branch || '',
        path: checkout.path
      }
    }) : []
    selectedId: header.checkout ? header.checkout.id : ''
    displayOnly: header.displayOnly || !header.navigationEnabled
    pointerGate: header.pointerGate
    onSelected: function (id) {
      if (header.project)
        header.checkoutRequested(header.project.id, id)
    }
  }
  onVisibleChanged: if (!visible) {
    checkoutPicker.close()
    profilePicker.close()
  }
  onProjectChanged: {
    checkoutPicker.close()
    profilePicker.close()
  }
  spacing: Style.space(8)
  GridLayout {
    Layout.fillWidth: true
    columns: header.width < Style.space(440) ? 1 : 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(8)
    Aranea.UiLabel {
      Layout.fillWidth: true
      text: header.project ? header.project.name : ''
      font.pixelSize: Style.font.heading
      font.bold: true
      maximumLineCount: header.width < Style.space(440) ? 3 : 2
      elide: Text.ElideRight
      ToolTip.visible: nameHover.hovered
      ToolTip.text: text
      HoverHandler {
        id: nameHover
      }
    }
    Aranea.ActionButton {
      objectName: 'projectPrimaryStart'
      Layout.fillWidth: header.width < Style.space(440)
      text: header.acceptanceUnknown ? 'Launch status unknown' : header.pending ? 'Preparing…' : 'Start working'
      enabled: !header.displayOnly && !header.pending && !header.acceptanceUnknown && header.openAvailable && !!header.profile
      pointerGate: header.pointerGate
      onClicked: if (header.profile)
        header.chooseProfile(header.profile.id)
    }
  }
  RowLayout {
    Layout.fillWidth: true
    Aranea.ActionButton {
      objectName: 'headerChooseProject'
      visible: header.compact
      text: 'Choose project'
      enabled: !header.displayOnly && header.navigationEnabled
      pointerGate: header.pointerGate
      onClicked: header.projectPickerRequested()
    }
    Aranea.ActionButton {
      objectName: 'headerChooseCheckout'
      Layout.fillWidth: true
      text: 'Checkout · ' + header.branchText
      enabled: !header.displayOnly && header.navigationEnabled && !!header.project && header.project.checkouts.length > 0
      pointerGate: header.pointerGate
      onClicked: checkoutPicker.open()
    }
  }
  Aranea.UiLabel {
    Layout.fillWidth: true
    text: header.checkout ? header.checkout.path : 'No registered checkout'
    technical: true
    opacity: 0.7
    wrapMode: Text.NoWrap
    elide: Text.ElideMiddle
    ToolTip.visible: pathHover.hovered
    ToolTip.text: text
    HoverHandler {
      id: pathHover
    }
  }
  Aranea.UiLabel {
    objectName: 'projectProfileSummary'
    Layout.fillWidth: true
    text: (header.profile ? header.profile.name + ' · ' : '') + header.profileSummary
    opacity: 0.8
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Aranea.ActionButton {
      objectName: 'headerChooseProfile'
      text: 'Choose another profile'
      visible: !!header.project && (header.project.profiles || []).length > 0
      enabled: !header.displayOnly && !header.pending && !header.acceptanceUnknown && header.openAvailable
      pointerGate: header.pointerGate
      onClicked: profilePicker.open()
    }
    Aranea.ActionButton {
      objectName: 'headerManageProfiles'
      visible: !header.managementActive
      text: header.project && (header.project.profiles || []).length ? 'Manage profiles' : 'Set up a profile'
      variant: 'quiet'
      pointerGate: header.pointerGate
      onClicked: header.manageProfilesRequested()
    }
  }
}
