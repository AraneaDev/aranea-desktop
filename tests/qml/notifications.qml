// Behaviour of the notification service (Service.qml) with no toast windows
// and no notification server, its state under the sandbox HOME: a toast held
// on two screens stays paused until both copies let go, a clear while the
// inbox loads keeps it empty, pruning an old entry dismisses it at its
// sender, and a DND toggle survives the service going away at once.
import QtQuick
import Quickshell
import Quickshell.Io
import "lib"
import "fixtures/notification-hyprland"
import "plugins/araneadev.notifications" as Notif
import "plugins/araneadev.projects" as Projects
import "plugins/araneadev.notifications/NotificationLogic.js" as Logic

ShellRoot {
  // Not `shell`: the service has a `shell` property that would shadow it.
  id: testRoot

  // Test start in ms; entry timestamps are relative to it.
  readonly property real now: Date.now()
  // State root for the services under test.
  readonly property string stateRoot: Quickshell.env("HOME") + "/state-"

  QmlTest {
    id: t
  }

  Notif.Service {
    id: svc
    windowEnabled: false
    serverEnabled: false
    stateDir: testRoot.stateRoot + "a/"
  }

  Projects.ProjectRuntime {
    id: ipcTransport
  }

  // Call the real isolated notification IPC endpoint and inspect its reply.
  function ipc(method, want, then) {
    var config = decodeURIComponent(Qt.resolvedUrl('.').toString().replace(/^file:\/\//, ''))
    ipcTransport.run(['/usr/bin/qs', 'ipc', '-p', config, 'call', 'notifications', method], '', function (code, output, error) {
      t.equal(String(output || '').trim(), want, method + ' IPC reply')
      then()
    })
  }

  // Create a plain row and a controlled sender with distinct callable choices.
  function keyboardRow(id, names) {
    var ref = {
      tracked: true,
      actions: names.map(function (name) {
        return {
          identifier: name,
          text: name,
          invoke: function () {
            invokedActions.push(name)
          }
        }
      }),
      dismiss: function () {
        this.tracked = false
      }
    }
    svc.liveRefs[id] = ref
    var row = Logic.snapshotOf({
      id: id,
      appName: 'guessed-app'
    }, testRoot.now + id)
    svc.popupModel.insert(0, row)
    return ref
  }

  // Exercise shortcut policy, stable selection, exits and inbox preservation.
  function checkKeyboard(then) {
    invokedActions = []
    svc.inbox.upsert({
      timestamp: testRoot.now,
      originalId: 999,
      app: 'retained',
      summary: 'keep me'
    })
    var inboxBefore = svc.inbox.count
    t.equal(inboxBefore, 1, 'shortcut test starts with a retained inbox entry')
    ipc('act', 'none', function () {
      ipc('keyboard', 'none', function () {
        keyboardRow(61, [])
        ipc('act', 'ok', function () {
          t.equal(svc.popupModel.count, 0, 'guessed display name alone dismisses')
          keyboardRow(62, ['default'])
          ipc('act', 'ok', function () {
            t.equal(invokedActions, ['default'], 'only default click invokes')
            keyboardRow(63, ['button'])
            ipc('act', 'ok', function () {
              t.equal(invokedActions, ['default', 'button'], 'only button invokes')
              keyboardRow(64, ['default', 'button'])
              ipc('act', 'ok', function () {
                t.check(svc.keyboardMode, 'default plus button enters keyboard mode')
                t.equal(svc.keyboardOriginalId, 64, 'keyboard retains original card identity')
                t.check(svc.popupHeld(String(testRoot.now + 64) + '-64'), 'keyboard pauses expiry')
                keyboardRow(65, ['other'])
                svc.keyboardPressed(Qt.Key_9, '9')
                t.check(svc.keyboardMode, 'out-of-range number keeps the selected card')
                svc.popupModel.move(1, 0, 1)
                svc.keyboardPressed(Qt.Key_2, '2')
                t.equal(invokedActions, ['default', 'button', 'button'], 'number two invokes button after visible click')
                t.equal(svc.popupModel.get(0).originalId, 65, 'insertion never redirects selection')
                t.check(!svc.keyboardMode, 'choice releases keyboard')
                t.check(!svc.popupHeld(String(testRoot.now + 65) + '-65'), 'choice resumes expiry')
                svc.clearPopups()
                keyboardRow(66, ['left', 'right'])
                ipc('act', 'ok', function () {
                  t.check(svc.keyboardMode, 'two buttons enter keyboard mode')
                  svc.keyboardPressed(Qt.Key_Down, '')
                  svc.keyboardPressed(Qt.Key_Return, '')
                  t.equal(invokedActions, ['default', 'button', 'button', 'right'], 'Enter invokes selected visible choice')
                  keyboardRow(67, ['stale', 'never'])
                  ipc('keyboard', 'on', function () {
                    svc.expirePopup(0)
                    keyboardRow(68, ['neighbour'])
                    svc.keyboardPressed(Qt.Key_1, '1')
                    t.equal(invokedActions, ['default', 'button', 'button', 'right'], 'expired selection never falls through')
                    t.check(!svc.keyboardMode, 'expiry releases keyboard')
                    svc.clearPopups()
                    keyboardRow(69, ['before', 'second'])
                    svc.startKeyboard(69)
                    svc.removePopupsByOriginalId(69)
                    keyboardRow(69, ['after', 'second'])
                    svc.keyboardPressed(Qt.Key_1, '1')
                    t.equal(invokedActions, ['default', 'button', 'button', 'right'], 'same-ID replacement refuses stale key')
                    svc.clearPopups()
                    keyboardRow(70, ['escape', 'unused'])
                    ipc('keyboard', 'on', function () {
                      svc.keyboardPressed(Qt.Key_Escape, '')
                      t.check(!svc.keyboardMode && !svc.popupHeld('any'), 'Escape releases focus and timer pause')
                      ipc('keyboard', 'on', function () {
                        ipc('keyboard', 'off', function () {
                          t.check(!svc.keyboardMode, 'IPC toggles ownership off')
                          svc.startKeyboard(70)
                          svc.clearPopups()
                          t.check(!svc.keyboardMode, 'clear releases keyboard')
                          t.equal(svc.inbox.count, inboxBefore, 'shortcuts leave persistent inbox unchanged')
                          t.equal(svc.inbox.model.get(0).summary, 'keep me', 'shortcuts preserve retained inbox content')
                          var closingDefault = keyboardRow(71, ['default', 'unused'])
                          closingDefault.actions[0].invoke = function () {
                            invokedActions.push('closing-default')
                            svc.removePopupsByOriginalId(71)
                            keyboardRow(72, ['survivor'])
                          }
                          svc.startKeyboard(71)
                          svc.keyboardPressed(Qt.Key_Return, '')
                          t.equal(invokedActions[invokedActions.length - 1], 'closing-default', 'Enter invokes meaningful card click before its buttons')
                          t.equal(svc.popupModel.get(0).originalId, 72, 'synchronous default callback cannot consume a replacement card')
                          svc.clearPopups()
                          checkCenterExit(then)
                        })
                      })
                    })
                  })
                })
              })
            })
          })
        })
      })
    })
  }

  // Actual service selection/dispatch with only native compositor IO adapted.
  function checkSenderWindows() {
    function windows(records) {
      Hyprland.toplevels = {
        values: records.map(function (record) {
          return {
            lastIpcObject: record
          }
        })
      }
    }
    function row(id, name, pid) {
      svc.popupModel.insert(0, Logic.snapshotOf({
        id: id,
        appName: name,
        hints: {
          "sender-pid": pid
        }
      }, testRoot.now + id))
    }
    var telegram = {
      class: "org.telegram.desktop",
      address: "0xabc",
      pid: 101,
      title: "Telegram",
      focusHistoryID: 0
    }
    var terminal = {
      class: "foot",
      address: "0xdef",
      pid: 202,
      title: "Terminal",
      focusHistoryID: 1
    }
    windows([telegram, terminal])
    row(80, "Telegram Desktop", 202)
    t.check(svc.popupHasMeaningfulClick(80), "current sender PID window is a meaningful click")
    svc.startKeyboard(80)
    svc.keyboardPressed(Qt.Key_Return, "")
    t.equal(Hyprland.dispatched, ['hl.dsp.focus({window = hl.get_window("address:0xdef")})'], "keyboard focuses PID window before conflicting display class")
    t.equal(svc.popupModel.count, 0, "verified sender click consumes its own card")
    row(81, "Telegram Desktop", 202)
    svc.startKeyboard(81)
    terminal = {
      class: "foot",
      address: "0xbeef",
      pid: 202,
      title: "Replacement",
      focusHistoryID: 1
    }
    windows([telegram, terminal])
    svc.keyboardPressed(Qt.Key_1, "1")
    t.equal(Hyprland.dispatched.length, 1, "changed address refuses stale keyboard choice")
    t.check(!svc.keyboardMode && svc.popupModel.count === 1, "target replacement releases keyboard without consuming card")
    svc.startKeyboard(81)
    windows([telegram])
    svc.keyboardPressed(Qt.Key_Return, "")
    t.equal(Hyprland.dispatched.length, 1, "closed PID window never redirects key to class fallback")
    svc.clearPopups()
    row(82, "Telegram Desktop", 0)
    t.check(!svc.popupHasMeaningfulClick(82), "class fallback never becomes meaningful keyboard click")
    svc.invokePopupDefault(0)
    t.equal(Hyprland.dispatched[1], 'hl.dsp.focus({window = hl.get_window("address:0xabc")})', "pointer matches literal multi-word class suffix by address")
    windows([telegram,
      {
        class: "org.telegram.desktop",
        address: "0xaaa",
        pid: 303
      }
    ])
    row(83, "Telegram Desktop", 0)
    svc.invokePopupDefault(0)
    t.equal(Hyprland.dispatched.length, 2, "ambiguous class fallback leaves focus alone")
    windows([
      {
        class: "anything",
        address: "0xaaa",
        pid: 303
      }
    ])
    row(84, ".*", 0)
    svc.invokePopupDefault(0)
    t.equal(Hyprland.dispatched.length, 2, "display name never executes as a regex")
    windows([
      {
        class: "foot",
        address: '0xabc\";bad',
        pid: 202
      }
    ])
    row(85, "foot", 202)
    t.check(!svc.popupHasMeaningfulClick(85), "invalid observed address is not meaningful")
    svc.invokePopupDefault(0)
    t.equal(Hyprland.dispatched.length, 2, "invalid address never enters dispatch")
    windows([telegram])
    row(86, "Telegram Desktop", 101)
    svc.startKeyboard(86)
    windows([
      {
        class: "org.telegram.desktop",
        address: "0xabc",
        pid: 101
      }
    ])
    svc.keyboardPressed(Qt.Key_Return, "")
    t.equal(Hyprland.dispatched.length, 2, "reused address and PID cannot replace native window identity")
    svc.clearPopups()
    windows([telegram,
      {
        class: "foot",
        address: "0xbbb",
        pid: 101
      }
    ])
    row(87, "unknown-app", 101)
    t.check(!svc.popupHasMeaningfulClick(87), "multiple windows for one PID do not invent a target")
    svc.invokePopupDefault(0)
    t.equal(Hyprland.dispatched.length, 2, "ambiguous PID without unique class leaves focus alone")
    windows([telegram])
    var native = keyboardRow(88, ["default"])
    svc.popupModel.setProperty(0, "senderPid", 101)
    svc.invokePopupDefault(0)
    t.equal(invokedActions, ["default"], "native default retains precedence over PID focus")
    t.equal(Hyprland.dispatched.length, 2, "native default does not also focus sender window")
    svc.liveRefs[88] = native
    svc.popupModel.insert(0, Logic.snapshotOf({
      id: 88,
      hints: {
        "sender-pid": 101,
        "omarchy-exec-argv": '["/usr/bin/true"]'
      }
    }, testRoot.now + 88))
    svc.invokePopupDefault(0)
    t.equal(invokedActions, ["default"], "literal argv retains precedence over native default")
    t.equal(Hyprland.dispatched.length, 2, "literal argv does not also focus PID window")
    invokedActions = []
    Hyprland.toplevels = {
      values: []
    }
    svc.clearPopups()
  }

  // Unnamed senders have independent protocol identities, never a shared stack.
  function checkUnnamed(then) {
    function notification(id) {
      return {
        id: id,
        appName: "",
        summary: "unnamed " + id,
        urgency: 0,
        hints: {
          transient: true
        },
        tracked: false,
        closed: senderSignals.closed,
        dismiss: function () {
          this.tracked = false
        }
      }
    }
    svc.handleNotification(notification(89))
    svc.handleNotification(notification(90))
    t.step(20, function () {
      t.equal(svc.popupModel.count, 2, "two unnamed notifications remain separate visible rows")
      t.equal([svc.popupModel.get(0).originalId, svc.popupModel.get(1).originalId], [90, 89], "unnamed cards retain distinct IDs and newest order")
      svc.dismissPopup(0)
      t.equal(svc.popupModel.get(0).originalId, 89, "dismissing unnamed card leaves the other card")
      svc.clearPopups()
      then()
    })
  }

  // Opening the inbox transfers ownership away from the toast shortcuts.
  function checkCenterExit(then) {
    var requests = []
    svc.shell = {
      toggle: function (plugin) {
        requests.push(plugin)
      }
    }
    keyboardRow(74, ['first', 'second'])
    svc.startKeyboard(74)
    ipc('showHistory', 'ok', function () {
      t.check(!svc.keyboardMode && !svc.popupHeld('any'), 'opening notification center releases toast keyboard and timers')
      t.equal(requests, ['araneadev.notifications'], 'history shortcut routes to Aranea center')
      svc.shell = null
      svc.clearPopups()
      then()
    })
  }

  // A second service, created and destroyed by the DND check.
  Component {
    id: serviceComponent
    Notif.Service {
      windowEnabled: false
      serverEnabled: false
      stateDir: testRoot.stateRoot + "b/"
    }
  }

  // Stands in for a sender's live Notification object.
  QtObject {
    id: fakeRef
    property bool tracked: true
    property int dismissed: 0

    // Records a dismiss at the sender.
    function dismiss() {
      dismissed += 1
    }
  }

  // Observed release signal from the service being destroyed.
  property bool keyboardReleasedOnTeardown: false
  // Records native sender invocations independently from model removals.
  property var invokedActions: []
  QtObject {
    id: actionRef
    property bool tracked: true
    property var actions: [
      {
        identifier: "default",
        text: "Default",
        invoke: function () {
          invokedActions.push("default")
        }
      },
      {
        identifier: "open",
        text: "Open",
        invoke: function () {
          invokedActions.push("open")
        }
      },
      {
        identifier: "cut",
        text: "Omacut",
        invoke: function () {
          invokedActions.push("cut")
        }
      }
    ]
    function dismiss() {
      tracked = false
    }
  }

  QtObject {
    id: senderSignals
    signal closed
    signal hintsChanged
    signal actionsChanged
  }

  // Only the native Notification boundary is replaced: production delivery,
  // watchers, replacement and sender-close handling all run unchanged.
  function checkActionLifetime(then) {
    var first = {
      id: 41,
      appName: "omarchy-action",
      urgency: 0,
      tracked: false,
      hints: {
        "omarchy-actions": '[{"label":"Open","argv":["/usr/bin/false"]}]'
      },
      actions: [
        {
          identifier: "old",
          text: "Old",
          invoke: function () {
            invokedActions.push("old")
          }
        }
      ],
      closed: senderSignals.closed,
      hintsChanged: senderSignals.hintsChanged,
      actionsChanged: senderSignals.actionsChanged,
      dismiss: function () {
        this.tracked = false
        senderSignals.closed()
      }
    }
    svc.handleNotification(first)
    t.step(20, function () {
      t.check(first.tracked, "delivery keeps sender alive for actions")
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Open", "Old"], "hint buttons precede sender buttons")
      var revision = svc.actionsRevision
      first.hints = {
        "omarchy-actions": '[{"label":"Omacut","argv":["/usr/bin/false"]}]',
        "sender-pid": 505
      }
      senderSignals.hintsChanged()
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut", "Old"], "replacement refreshes action hints in the same popup")
      t.equal(svc.popupModel.count, 1, "replacement never duplicates the popup")
      t.equal(svc.popupModel.get(0).senderPid, 505, "sender-pid hint updates the existing popup role")
      first.hints["sender-pid"] = "505"
      senderSignals.hintsChanged()
      t.equal(svc.popupModel.get(0).senderPid, 0, "malformed replacement sender-pid cannot retain old target")
      t.check(svc.actionsRevision > revision, "replacement invalidates rendered action choices")
      first.actions = [
        {
          identifier: "new",
          text: "New",
          invoke: function () {
            invokedActions.push("new")
          }
        }
      ]
      senderSignals.actionsChanged()
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut", "New"], "sender action updates are observed")
      svc.startKeyboard(41)
      first.actions = [
        {
          identifier: "new",
          text: "New",
          invoke: function () {
            invokedActions.push("replacement-new")
          }
        }
      ]
      senderSignals.actionsChanged()
      t.check(!svc.keyboardMode, "same-label sender replacement ends keyboard ownership")
      svc.keyboardPressed(Qt.Key_2, "2")
      t.equal(invokedActions, [], "same-label replacement refuses stale numbered choice")
      svc.startKeyboard(41)
      first.tracked = false
      senderSignals.closed()
      t.check(!svc.keyboardMode, "sender close releases keyboard ownership")
      t.equal(svc.actionsFor(41).map(function (a) {
        return a.label
      }), ["Omacut"], "sender close removes only live libnotify buttons")
      t.equal(svc.invokePopupAction(41, 1), false, "closed sender choice cannot run")
      t.equal(invokedActions, [], "replacement and close never invoke stale actions")
      svc.clearPopups()
      first.hints = {}
      first.actions = [
        {
          identifier: "close",
          text: "Close",
          invoke: function () {
            first.tracked = false
            senderSignals.closed()
          }
        }
      ]
      svc.handleNotification(first)
      t.step(20, function () {
        t.equal(svc.invokePopupAction(41, 0), true, "a sender may close synchronously while its action runs")
        t.equal(svc.popupModel.count, 0, "a synchronously closed sender still consumes its own card")
        svc.clearPopups()
        then()
      })
    })
  }

  FileView {
    id: actionReader
    blockLoading: true
    path: testRoot.stateRoot + "actions.json"
  }

  // Exercise the production button protocol and literal argv process boundary.
  function checkActions(then) {
    var row = Logic.snapshotOf({
      id: 31,
      appName: "omarchy-action"
    }, testRoot.now)
    svc.popupModel.append(row)
    svc.liveRefs = ({
        31: actionRef
      })
    t.equal(svc.actionsFor(31).map(function (a) {
      return a.label
    }), ["Open", "Omacut"], "default click is separate from sender buttons")
    // Another card took visual slot zero after the first card was rendered.
    svc.popupModel.insert(0, Logic.snapshotOf({
      id: 32
    }, testRoot.now + 1))
    t.equal(svc.invokePopupAction(31, 1), true, "action targets stable original identity after insertion")
    t.equal(invokedActions, ["cut"], "selected live sender action invoked exactly once")
    t.equal(svc.popupModel.get(0).originalId, 32, "newer card was not invoked or removed")
    t.equal(svc.invokePopupAction(31, 0), false, "removed card cannot fall through to its neighbour")
    svc.clearPopups()
    svc.liveRefs = ({})
    svc.popupModel.append(row)
    t.equal(svc.actionsFor(31), [], "restored entries never revive sender actions")
    t.equal(svc.invokePopupAction(31, 0), false, "a dead sender action cannot run")
    svc.clearPopups()

    // Exercise real Util.execArgv at the process boundary, recording literals.
    var argv = ["/usr/bin/python3", "-c", "import json,sys;json.dump(sys.argv[2:],open(sys.argv[1], 'w'))", actionReader.path, "/tmp/a b.mp4", "a\"b", "$(touch nope)", "a;b"]
    var hint = JSON.stringify([
      {
        label: "Open",
        argv: ["/usr/bin/false"]
      },
      {
        label: "Omacut",
        argv: argv
      }
    ])
    var execRow = Logic.snapshotOf({
      id: 33,
      hints: {
        "omarchy-actions": hint
      }
    }, testRoot.now)
    svc.popupModel.append(execRow)
    t.equal(svc.actionsFor(33).map(function (a) {
      return a.label
    }), ["Open", "Omacut"], "argv buttons preserve visible order")
    t.equal(svc.invokePopupAction(33, -1), false, "negative choice refused")
    t.equal(svc.invokePopupAction(33, 2), false, "out-of-range choice refused")
    t.equal(svc.invokePopupAction(33, 1), true, "selected argv action launches")
    t.equal(svc.invokePopupAction(33, 1), false, "consumed action cannot launch twice")
    t.waitFor(function () {
      actionReader.reload()
      return actionReader.text().length > 0
    }, 5000, "argv action recorder finishes", function () {
      t.equal(JSON.parse(actionReader.text()), ["/tmp/a b.mp4", "a\"b", "$(touch nope)", "a;b"], "argv metacharacters survive process execution literally")
      then()
    })
  }

  // Reads the second service's settings file.
  FileView {
    id: settingsReader
    blockLoading: true
  }

  // The second service's settings file, parsed; {} while missing or torn.
  function savedSettings() {
    try {
      return JSON.parse(settingsReader.text())
    } catch (e) {
      return {}
    }
  }

  Component.onCompleted: {
    // A toast hovered on two screens: paused until both copies let go.
    svc.holdPopup("1-1", true)
    svc.holdPopup("1-1", true)
    t.check(svc.popupHeld("1-1"), "hovered toast is paused")
    svc.holdPopup("1-1", false)
    t.check(svc.popupHeld("1-1"), "still paused while the other screen holds it")
    svc.holdPopup("1-1", false)
    t.check(!svc.popupHeld("1-1"), "released on both screens")

    // Clear before the inbox has loaded: the loaded entries stay gone.
    t.check(!svc.inbox.loadedOnce, "inbox still loading")
    svc.inbox.clear()
    svc.inbox.finishLoad(JSON.stringify({
      timestamp: testRoot.now - 1000,
      originalId: 7,
      app: "mail",
      summary: "loaded late"
    }) + "\n")
    t.equal(svc.inbox.count, 0, "a clear during load wins over the loaded entries")

    t.waitFor(function () {
      return svc.inbox.loadedOnce && svc.settingsLoaded
    }, 10000, "the first service loads", function () {
      // An entry older than a week is pruned and dismissed at its sender.
      var old = {
        timestamp: testRoot.now - 8 * 24 * 3600 * 1000,
        originalId: 9,
        app: "chat",
        summary: "stale"
      }
      var refs = {}
      refs["" + old.timestamp + "-9.json"] = fakeRef
      svc.inboxRefs = refs
      svc.inbox.upsert(old)
      t.equal(svc.inbox.count, 0, "old entry pruned")
      t.equal(fakeRef.dismissed, 1, "pruning dismisses the entry at its sender")

      checkSenderWindows()
      checkUnnamed(function () {
        checkActionLifetime(function () {
          checkActions(function () {
            checkKeyboard(function () {
              // DND on, then the service goes before its debounced save fires.
              var second = serviceComponent.createObject(testRoot)
              t.waitFor(function () {
                return second.settingsLoaded
              }, 10000, "the second service loads its settings", function () {
                t.check(second.settingsLoaded, "second service loaded its settings")
                second.setDoNotDisturb(true)
                second.popupModel.append(Logic.snapshotOf({
                  id: 900
                }, testRoot.now))
                second.startKeyboard(900)
                second.keyboardModeChanged.connect(function () {
                  if (!second.keyboardMode)
                    testRoot.keyboardReleasedOnTeardown = true
                })
                t.check(second.popupHeld('any'), 'service teardown begins with keyboard expiry pause')
                second.destroy()
                settingsReader.path = testRoot.stateRoot + "b/notifications.json"
                t.waitFor(function () {
                  settingsReader.reload()
                  return testRoot.savedSettings().dnd !== undefined
                }, 5000, "the settings file is written", function () {
                  t.equal(testRoot.savedSettings().dnd, true, "DND written when the service goes away")
                  t.check(testRoot.keyboardReleasedOnTeardown, 'service teardown explicitly releases keyboard ownership')
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  }
}
