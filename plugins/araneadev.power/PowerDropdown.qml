// The Aranea Power dropdown's view: the hero (the battery cell, "Battery",
// the status line and the big percentage), the details grid, the CHARGE
// history, the live POWER DRAW trace, the POWER PROFILE pills and the key
// hint. Drawn from one plain view object (Panel.powerView) plus
// fast-changing properties kept out of it (the status fade, the history
// segments, the draw samples, the current percentage), and reporting every
// user action through a single action signal. No UPower objects and no
// process logic here: the view gets ready strings, so tests drive it with
// fixtures.
//
// The graphs arrive late and push the pills down under a still pointer,
// so any section changing height or visibility stamps layoutChangedAt;
// a pill click within 300 ms of that, or of the pill being built, is
// ignored unless the pointer has really moved onto it since.
pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "../araneadev.shared" as Aranea
import "../araneadev.shared/ClickSettle.js" as ClickSettle

Column {
  id: dropdown

  // View state built by Panel.powerView: {hero: {fraction, status,
  // percent} or null, details: [{label, value}], history: {visible,
  // summary, startLabel}, draw: {visible, caption}, profiles: [{key,
  // label, glyph}] (stable regardless of which is selected, so a
  // selection change never rebuilds the pills), selectedProfile (string,
  // the key the pills mark chosen), pendingProfile (string, a request not
  // yet confirmed by a refresh; "" for none, pulses that pill busy),
  // cursor: {active, section, index}, keyHint}.
  property var view: ({})
  // Opacity of the hero's status line, for the phrase fade.
  property real statusOpacity: 1
  // Charge history segments from PowerLogic.historyPoints in unit
  // coordinates (width 1, height 1): [[{x, y}]].
  property var historySegments: []
  // Power draw samples, oldest first: [{rx: watts, tx: 0}].
  property var drawSamples: []
  // The current charge in percent, for the history's dot; -1 for none.
  property real nowPercent: -1
  // Cursor object from the view, or a neutral one.
  readonly property var cursor: view && view.cursor ? view.cursor : ({
      active: false,
      section: "",
      index: -1
    })
  // The view's hero, or null when there is no battery.
  readonly property var hero: view && view.hero ? view.hero : null
  // The view's detail pairs, or [].
  readonly property var details: view && Array.isArray(view.details) ? view.details : []
  // The view's history section, or a hidden one.
  readonly property var history: view && view.history ? view.history : ({
      visible: false
    })
  // The view's draw section, or a hidden one.
  readonly property var draw: view && view.draw ? view.draw : ({
      visible: false
    })
  // The view's profile pills, or [].
  readonly property var profiles: view && Array.isArray(view.profiles) ? view.profiles : []
  // The key the pills mark selected (view.selectedProfile), or "".
  readonly property string selectedProfile: view && typeof view.selectedProfile === "string" ? view.selectedProfile : ""
  // A request not yet confirmed by a refresh (view.pendingProfile); "" for
  // none. The pill with this key pulses busy.
  readonly property string pendingProfile: view && typeof view.pendingProfile === "string" ? view.pendingProfile : ""
  // Filters synthetic hover from pills moving under a still pointer, and
  // carries layoutChangedAt to the pills that settle clicks.
  readonly property alias pointerGate: gate
  // When the layout last shifted under the pointer (Date.now()), 0 for
  // never; see noteLayoutChange.
  property real layoutChangedAt: 0

  // Emitted for every user action, NAME with its ARG:
  //   setProfile ({index, key}): a profile pill was clicked;
  //   hover ({section: "profiles", index, key}): the pointer moved onto a
  //     pill (through the gate).
  // Both carry the profile's key as the view saw it, so the host can refuse
  // one whose pill changed underneath the click.
  signal action(string name, var arg)

  // Stamps layoutChangedAt: something moved the pills without rebuilding
  // them.
  function noteLayoutChange() {
    dropdown.layoutChangedAt = Date.now()
  }

  // Resets the pointer gate; called after every keyboard-driven move so a
  // stale pointer sample never steals the cursor back.
  function disarmPointer() {
    gate.reset()
  }

  // The cursor's index in SECTION, or -1 when the cursor isn't active there.
  function cursorIn(section) {
    return cursor.active && cursor.section === section ? cursor.index : -1
  }

  // Profile INDEX's key, or "" when there's no such profile.
  function keyAt(index) {
    var row = dropdown.profiles[index]
    return row && typeof row.key === "string" ? row.key : ""
  }

  spacing: Style.space(10)

  // A hairline above a section, shown with it.
  component Separator: Rectangle {
    objectName: "separator"
    width: parent ? parent.width : 0
    height: Math.max(1, Style.spacing.hairline)
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.08)
  }

  // A section caption with optional muted text on the right content edge.
  component Caption: Item {
    id: caption
    // The caption, e.g. "CHARGE".
    property string title: ""
    // The trailing text, e.g. "100% → 62%".
    property string trailing: ""
    // The trailing text's objectName, for tests.
    property string trailingName: ""

    width: parent ? parent.width : 0
    implicitHeight: Math.max(captionTitle.implicitHeight, captionTrailing.implicitHeight)
    Text {
      id: captionTitle
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: caption.title
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.uiFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      font.letterSpacing: 0
    }
    Text {
      id: captionTrailing
      objectName: caption.trailingName
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      text: caption.trailing
      color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
      font.family: Aranea.Typography.technicalFamily
      font.pixelSize: Style.font.caption
    }
  }

  PowerHero {
    width: parent.width
    visible: dropdown.hero !== null
    fraction: dropdown.hero ? Number(dropdown.hero.fraction) || 0 : 0
    status: dropdown.hero ? dropdown.hero.status || "" : ""
    statusOpacity: dropdown.statusOpacity
    percent: dropdown.hero ? String(dropdown.hero.percent || "") : ""
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()
  }
  Separator {
    visible: detailsSection.visible
  }
  Grid {
    id: detailsSection
    objectName: "detailsSection"
    // Each label-value pair's width: half the row.
    readonly property real pairWidth: (width - columnSpacing) / 2
    width: parent.width
    visible: dropdown.details.length > 0
    columns: 2
    columnSpacing: Style.space(12)
    rowSpacing: Style.space(4)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    Repeater {
      model: dropdown.details
      Item {
        id: pair
        required property var modelData
        width: detailsSection.pairWidth
        implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)
        Text {
          id: pairLabel
          objectName: "detailLabel"
          anchors.left: parent.left
          anchors.right: pairValue.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          text: pair.modelData.label || ""
          elide: Text.ElideRight
          color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
          font.family: Aranea.Typography.uiFamily
          font.pixelSize: Style.font.caption
        }
        Text {
          id: pairValue
          objectName: "detailValue"
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: pair.modelData.value || ""
          color: Aranea.DesignTokens.foreground
          font.family: Aranea.Typography.technicalFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
  Separator {
    visible: historySection.visible
  }
  Column {
    id: historySection
    objectName: "historySection"
    width: parent.width
    visible: !!dropdown.history.visible
    spacing: Style.space(4)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    Caption {
      title: "CHARGE"
      trailing: dropdown.history.summary || ""
      trailingName: "historySummary"
    }
    PowerHistory {
      width: parent.width
      segments: dropdown.historySegments
      nowPercent: dropdown.nowPercent
    }
    Item {
      width: parent.width
      implicitHeight: Math.max(startLabel.implicitHeight, nowLabel.implicitHeight)
      Text {
        id: startLabel
        objectName: "historyStart"
        anchors.left: parent.left
        text: dropdown.history.startLabel || ""
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.technicalFamily
        font.pixelSize: Style.font.caption
      }
      Text {
        id: nowLabel
        objectName: "historyNow"
        anchors.right: parent.right
        text: "now"
        color: Util.alpha(Aranea.DesignTokens.foreground, 0.55)
        font.family: Aranea.Typography.uiFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
  Separator {
    visible: drawSection.visible
  }
  Column {
    id: drawSection
    objectName: "drawSection"
    width: parent.width
    visible: !!dropdown.draw.visible
    spacing: Style.space(4)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    Caption {
      title: "POWER DRAW"
      trailing: dropdown.draw.caption || ""
      trailingName: "drawCaption"
    }
    PowerDraw {
      width: parent.width
      samples: dropdown.drawSamples
    }
  }
  Separator {
    visible: profilesSection.visible
  }
  Column {
    id: profilesSection
    objectName: "profilesSection"
    width: parent.width
    visible: dropdown.profiles.length > 0
    spacing: Style.space(8)
    onHeightChanged: dropdown.noteLayoutChange()
    onVisibleChanged: dropdown.noteLayoutChange()

    Caption {
      title: "POWER PROFILE"
    }
    Row {
      id: pillRow
      // Each pill's width: the row split evenly.
      readonly property real cellWidth: (width - spacing * (Math.max(1, dropdown.profiles.length) - 1)) / Math.max(1, dropdown.profiles.length)
      width: parent.width
      spacing: Style.space(6)

      Repeater {
        model: dropdown.profiles
        Item {
          id: cell
          required property var modelData
          required property int index
          // When this pill was built (Date.now()), for the settle guard.
          property real createdAt: 0

          // Whether a pointer click may choose this pill (the pill's
          // clickGate): settled since it was built and since the
          // dropdown's last layout shift, or moved onto since.
          function clickSettled() {
            return ClickSettle.clickSettled({
              now: Date.now(),
              createdAt: cell.createdAt,
              movedAt: pill.pointerMovedAt,
              layoutChangedAt: dropdown.layoutChangedAt
            })
          }

          width: pillRow.cellWidth
          height: pill.implicitHeight
          Component.onCompleted: cell.createdAt = Date.now()

          Aranea.FilamentPill {
            id: pill
            refined: true
            objectName: "profilePill"
            anchors.fill: parent
            text: cell.modelData.label || ""
            glyph: cell.modelData.glyph || ""
            selected: cell.modelData.key !== undefined && cell.modelData.key === dropdown.selectedProfile
            busy: dropdown.pendingProfile !== "" && cell.modelData.key === dropdown.pendingProfile
            hasCursor: dropdown.cursorIn("profiles") === cell.index
            pointerGate: dropdown.pointerGate
            clickGate: cell
            onClicked: dropdown.action("setProfile", {
              index: cell.index,
              key: dropdown.keyAt(cell.index)
            })
            onHoveredMoved: dropdown.action("hover", {
              section: "profiles",
              index: cell.index,
              key: dropdown.keyAt(cell.index)
            })
          }
        }
      }
    }
  }
  Text {
    objectName: "keyHint"
    width: parent.width
    topPadding: Style.space(4)
    text: dropdown.view && dropdown.view.keyHint ? dropdown.view.keyHint : ""
    color: Util.alpha(Aranea.DesignTokens.foreground, 0.3)
    font.family: Aranea.Typography.uiFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  PointerMoveGate {
    id: gate
    // The dropdown's last layout shift, for the pills' clickSettled().
    property real layoutChangedAt: dropdown.layoutChangedAt

    referenceItem: dropdown
  }
}
