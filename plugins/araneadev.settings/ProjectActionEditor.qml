// Presentation draft only; Save requests configuration and never starts a command.
pragma ComponentBehavior: Bound
// Host font tokens are runtime QObject properties.
// qmllint disable missing-property
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import "../araneadev.shared" as Aranea

ColumnLayout {
  id: editor
  // Captures prohibit even configuration requests.
  property bool displayOnly: false
  // One shared backend request may be in flight.
  property bool pending: false
  // Shared pointer settling boundary.
  property var pointerGate: null
  // Editable values are separate from saved definitions and immutable runs.
  property var draft: ({
      name: '',
      executable: '',
      cwdRelative: '.',
      kind: 'command',
      timeoutSeconds: '300',
      previewUrl: '',
      id: ''
    })
  // Store revision captured when editing began, never silently rebased.
  property int expectedRevision: 0
  // Local validation feedback remains plain text.
  property string fieldError: ''
  // Literal argument rows keep editing focus when their text changes.
  property alias argumentsModel: argumentsModel
  // Emit only a complete inert definition plus its original revision guard.
  signal saveRequested(var definition, int revision)
  // The caller closes the editor without any client request.
  signal cancelRequested
  // Uniform theme surface for friendly input fields; plain text stays selectable.
  component InputField: TextField {
    color: Color.foreground
    placeholderTextColor: Util.alpha(Color.foreground, 0.65)
    padding: Style.space(8)
    background: Rectangle {
      radius: Style.space(3)
      color: Util.alpha(Color.foreground, 0.065)
    }
  }
  ListModel {
    id: argumentsModel
  }
  // Begin a fresh draft from approved saved fields, preserving empty later arguments.
  function begin(definition: var, revision: int): void {
    var d = definition || {}
    draft = {
      id: d.id || '',
      name: d.name || '',
      executable: (d.argv || [])[0] || '',
      cwdRelative: d.cwdRelative || '.',
      kind: d.kind || 'command',
      timeoutSeconds: String(d.timeoutSeconds || 300),
      previewUrl: d.previewUrl || ''
    }
    expectedRevision = revision
    fieldError = ''
    argumentsModel.clear();
    (d.argv || []).slice(1).forEach(function (value) {
      argumentsModel.append({
        value: value
      })
    })
  }
  // Allowlisted local edits never persist or run.
  function setField(key: string, value: string): void {
    if (displayOnly || ['name', 'executable', 'cwdRelative', 'kind', 'timeoutSeconds', 'previewUrl'].indexOf(key) < 0)
      return
    draft = Object.assign({}, draft, {
      [key]: value
    })
    fieldError = ''
  }
  // Add one literal argument; an empty value is valid.
  function addArgument(): void {
    if (!displayOnly && argumentsModel.count < 63)
      argumentsModel.append({
        value: ''
      })
  }
  // Replace just one row, avoiding delegate/focus recreation while typing.
  function setArgument(index: int, value: string): void {
    if (!displayOnly && index >= 0 && index < argumentsModel.count)
      argumentsModel.setProperty(index, 'value', value)
  }
  // Remove only the selected argument, never split another row's text.
  function removeArgument(index: int): void {
    if (!displayOnly && index >= 0 && index < argumentsModel.count)
      argumentsModel.remove(index)
  }
  // Serialize presentation fields into the exact backend draft shape.
  function definition(): var {
    var argv = [draft.executable]
    for (var i = 0; i < argumentsModel.count; i++)
      argv.push(argumentsModel.get(i).value)
    var result = {
      name: draft.name,
      kind: draft.kind,
      argv: argv,
      cwdRelative: draft.cwdRelative,
      timeoutSeconds: draft.kind === 'command' ? Number(draft.timeoutSeconds) : null,
      previewUrl: draft.kind === 'service' && draft.previewUrl ? draft.previewUrl : null
    }
    if (draft.id)
      result.id = draft.id
    return result
  }
  // Friendly local errors complement authoritative backend validation.
  function validate(): string {
    var d = definition()
    var controls = /[\x00-\x1f\x7f]/;
    if (!d.name.trim() || d.name.length > 120 || controls.test(d.name))
      return 'Name must contain 1–120 plain text characters.'
    if (!d.argv[0] || d.argv[0].length > 1024 || controls.test(d.argv[0]) || !/^(?:[^/]+|\/.*|\.\/.*)$/.test(d.argv[0]))
      return 'Enter an executable name, absolute path or explicit ./path.'
    if (d.argv.length > 64)
      return 'Use at most 63 argument fields.'
    var total = 0
    for (var i = 0; i < d.argv.length; i++) {
      if (controls.test(d.argv[i]) || d.argv[i].length > 1024)
        return 'Each argument must have at most 1024 characters without control characters.'
      total += encodeURIComponent(d.argv[i]).replace(/%[0-9A-F]{2}/g, 'x').length
    }
    if (total > 16384)
      return 'Command arguments exceed 16 KiB.'
    if (!d.cwdRelative || d.cwdRelative.length > 512 || d.cwdRelative[0] === '/' || controls.test(d.cwdRelative) || d.cwdRelative.split('/').some(function (segment) {
      return segment === '..' || segment === ''
    }))
      return 'Working folder must be a relative path inside this checkout, without .. segments.'
    if (['command', 'service'].indexOf(d.kind) < 0)
      return 'Choose Command or Service.'
    if (d.kind === 'command' && (!/^\d+$/.test(draft.timeoutSeconds) || d.timeoutSeconds < 1 || d.timeoutSeconds > 3600))
      return 'Command timeout must be 1–3600 seconds.'
    if (d.previewUrl) {
      var match = /^https?:\/\/(?:127\.0\.0\.1|\[::1\]):([0-9]{1,5})(?:[/?][^#\s]*)?$/.exec(d.previewUrl)
      if (!match || Number(match[1]) < 1 || Number(match[1]) > 65535 || d.previewUrl.length > 2048 || controls.test(d.previewUrl))
        return 'Preview URL must use http or https, 127.0.0.1 or [::1], and an explicit port.'
    }
    return ''
  }
  // Saving is explicitly inert configuration; refusal keeps the caller's draft.
  function save(): void {
    if (displayOnly || pending)
      return
    fieldError = validate()
    if (!fieldError)
      saveRequested(definition(), expectedRevision)
  }
  // Cancel never invokes any backend.
  function cancel(): void {
    cancelRequested()
  }
  // Save only presentation values for inert capture restoration.
  function captureSnapshot(): var {
    return {
      draft: Object.assign({}, draft),
      argv: definition().argv.slice(1),
      expectedRevision: expectedRevision,
      fieldError: fieldError
    }
  }
  // Restore a draft without executing or implicitly rebasing its revision.
  function captureRestore(saved: var): void {
    if (!saved)
      return
    draft = saved.draft
    expectedRevision = saved.expectedRevision
    fieldError = saved.fieldError || ''
    argumentsModel.clear();
    (saved.argv || []).forEach(function (value) {
      argumentsModel.append({
        value: value
      })
    })
  }
  spacing: Style.space(8)
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Configure action'
    font.bold: true
  }
  SettingsLabel {
    Layout.fillWidth: true
    text: 'Saving approves this command for explicit Run or Start. Arguments are passed literally, one field per argument.'
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Repeater {
    model: [
      {
        key: 'name',
        label: 'Name'
      },
      {
        key: 'executable',
        label: 'Command executable'
      },
      {
        key: 'cwdRelative',
        label: 'Working folder (relative to checkout)'
      }
    ]
    ColumnLayout {
      id: field
      required property var modelData
      Layout.fillWidth: true
      SettingsLabel {
        text: field.modelData.label
      }
      InputField {
        objectName: field.modelData.key === 'executable' ? 'actionExecutable' : 'actionField:' + field.modelData.key
        Layout.fillWidth: true
        text: editor.draft[field.modelData.key] || ''
        readOnly: editor.displayOnly || editor.pending
        selectByMouse: true
        font.family: field.modelData.key === 'name' ? Aranea.Typography.uiFamily : Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
        onTextEdited: editor.setField(field.modelData.key, text)
      }
    }
  }
  SettingsLabel {
    text: 'Arguments'
    visible: argumentsModel.count > 0
  }
  Repeater {
    model: argumentsModel
    ColumnLayout {
      id: argument
      required property int index
      required property string value
      Layout.fillWidth: true
      InputField {
        objectName: 'actionArgument:' + argument.index
        Layout.fillWidth: true
        placeholderText: 'Argument ' + (argument.index + 1) + ' (empty is valid)'
        text: argument.value
        readOnly: editor.displayOnly || editor.pending
        selectByMouse: true
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
        onTextEdited: editor.setArgument(argument.index, text)
      }
      SettingsButton {
        text: 'Remove argument ' + (argument.index + 1)
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.removeArgument(argument.index)
      }
    }
  }
  SettingsButton {
    text: 'Add argument'
    enabled: !editor.displayOnly && !editor.pending && argumentsModel.count < 63
    pointerGate: editor.pointerGate
    onClicked: editor.addArgument()
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    Repeater {
      model: ['command', 'service']
      SettingsButton {
        id: kind
        required property string modelData
        text: modelData === 'command' ? 'Command' : 'Service'
        selected: editor.draft.kind === modelData
        enabled: !editor.displayOnly && !editor.pending
        pointerGate: editor.pointerGate
        onClicked: editor.setField('kind', kind.modelData)
      }
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: editor.draft.kind === 'command'
    SettingsLabel {
      text: 'Timeout (seconds)'
    }
    InputField {
      Layout.fillWidth: true
      objectName: 'actionTimeout'
      text: editor.draft.timeoutSeconds
      readOnly: editor.displayOnly || editor.pending
      font.pixelSize: Style.font.caption
      onTextEdited: editor.setField('timeoutSeconds', text)
    }
  }
  ColumnLayout {
    Layout.fillWidth: true
    visible: editor.draft.kind === 'service'
    SettingsLabel {
      Layout.fillWidth: true
      text: 'Preview URL (optional loopback URL with port)'
      wrapMode: Text.WrapAtWordBoundaryOrAnywhere
    }
    InputField {
      Layout.fillWidth: true
      objectName: 'actionPreviewUrl'
      text: editor.draft.previewUrl
      readOnly: editor.displayOnly || editor.pending
      font.pixelSize: Style.font.caption
      selectByMouse: true
      onTextEdited: editor.setField('previewUrl', text)
    }
  }
  SettingsLabel {
    Layout.fillWidth: true
    visible: !!editor.fieldError
    text: editor.fieldError
    color: Aranea.DesignTokens.attention
    wrapMode: Text.WrapAtWordBoundaryOrAnywhere
  }
  Flow {
    Layout.fillWidth: true
    spacing: Style.space(8)
    SettingsButton {
      objectName: 'actionSave'
      text: 'Save'
      enabled: !editor.displayOnly && !editor.pending
      pointerGate: editor.pointerGate
      onClicked: editor.save()
    }
    SettingsButton {
      objectName: 'actionCancel'
      text: 'Cancel'
      enabled: !editor.pending
      pointerGate: editor.pointerGate
      onClicked: editor.cancel()
    }
  }
}
