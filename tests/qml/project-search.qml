// Real menu/project-client lifecycle through a sandbox IPC boundary.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Complete owner projection supplied by the sandbox transport.
  property var snapshot: ({
      sessionId: "test-session",
      observedAt: 1,
      availability: {
        compositor: true
      },
      bindings: [],
      operations: [],
      projects: [
        {
          id: "p-aranea",
          name: "Aranea",
          lastCheckoutId: "c-main",
          workspaceMode: "dedicated",
          tools: {
            editorId: null,
            terminalId: null
          },
          commonDir: "/tmp/aranea/.git",
          associations: [
            {
              checkoutId: "c-main",
              mode: "dedicated",
              workspaceId: 7,
              separate: false
            }
          ],
          checkouts: [
            {
              id: "c-main",
              path: "/tmp/dev/aranea",
              branch: "main",
              primary: true
            },
            {
              id: "c-feature",
              path: "/tmp/dev/aranea-feature",
              branch: "feature",
              primary: false
            }
          ]
        }
      ]
    })
  // IPC argument arrays issued by the real client.
  property var calls: []
  // Held operation callback for lifecycle races.
  property var observation: null
  // Monotonic owner generation supplied independently of UI submissions.
  property int ownerGeneration: 1
  // Captured public details navigation requests.
  property var details: []
  // Generic owner refusal selected by the fixture.
  property bool refuse: false
  // Readiness-only refusals exercise client retries without accepted work.
  property bool readiness: false
  QmlTest {
    id: t
  }
  Menu.Menu {
    id: menu
    windowEnabled: false
    defaultMenuPath: Qt.resolvedUrl("fixtures/omarchy-menu.jsonc").toString().replace("file://", "")
    run: function (command) {
      t.check(false, "fixture never invokes shell commands")
    }
  }
  // Construct a key event consumed by the production menu.
  function key(code) {
    return {
      key: code,
      modifiers: Qt.NoModifier,
      text: "",
      accepted: false
    }
  }
  // Read the first visible result after real menu ranking.
  function row() {
    return menu.displayModel.count ? menu.displayModel.get(0) : null
  }
  // Sandbox IPC boundary; never executes commands or mutates a registry.
  function transport(argv, done) {
    host.calls = host.calls.concat([argv])
    if (argv[2] === "snapshot")
      done(0, JSON.stringify(host.snapshot), "")
    else if (argv[2] === "request")
      done(0, JSON.stringify(host.readiness ? {
        ok: false,
        error: {
          code: "OWNER_NOT_READY",
          message: "Owner is preparing"
        }
      } : host.refuse ? {
        ok: false,
        error: {
          code: "CHECKOUT_MISSING",
          message: "Checkout no longer exists"
        }
      } : {
        ok: true,
        operationId: "op-one",
        error: null
      }), "")
    else if (argv[2] === "operation")
      host.observation = done
    else
      t.check(false, "fixture refuses unknown IPC")
  }
  // Deliver an authoritative operation response to the real observer.
  function operation(state, outcome) {
    host.observation(0, JSON.stringify({
      id: "op-one",
      sessionId: host.snapshot.sessionId,
      generation: host.ownerGeneration,
      projectId: "p-aranea",
      checkoutId: "c-main",
      state: state,
      outcome: outcome,
      steps: [],
      error: outcome === "partial" ? {
        message: "Terminal was not observed"
      } : null
    }), "")
  }
  // Change the actual projected checkout without submitting or cancelling work.
  function chooseCheckout(id) {
    host.snapshot = JSON.parse(JSON.stringify(host.snapshot))
    host.snapshot.projects[0].lastCheckoutId = id
    menu.projectClient.snapshot = host.snapshot
    menu.desktopSearch.refreshNow()
  }
  // A different checkout must never borrow status, message, or visible outcome.
  function checkFeatureFeedbackAbsent(context) {
    t.check(row().detail.indexOf("/tmp/dev/aranea-feature") >= 0, context + " shows the feature checkout path")
    t.equal(row().actionStatus, "", context + " does not inherit main status")
    t.equal(row().actionMessage, "", context + " does not inherit main message")
    t.check(row().detail.indexOf("Project ready") < 0 && row().detail.indexOf("Terminal was not observed") < 0 && row().detail.indexOf("Checkout no longer exists") < 0, context + " does not inherit visible main outcome")
  }

  // Count submissions independently of snapshot and observer reads.
  function requests() {
    return host.calls.filter(function (argv) {
      return argv[2] === "request"
    }).length
  }
  Component.onCompleted: {
    if (!menu.projectClient) {
      t.check(false, "root search composes the project client")
      t.done()
      return
    }
    // Install the sandbox transport while inert, before any open/refresh.
    var client = menu.projectClient
    client.runner = host.transport
    client.pollInterval = 10000
    client.snapshot = host.snapshot
    t.check(client.captureActive, "offscreen preview starts inert")
    t.check(!client.request({
      projectId: "p-aranea",
      checkoutId: "c-main"
    }), "preview refuses actual project requests")
    client.captureActive = false
    menu.desktopSearch.runner = function (argv) {
      host.details = host.details.concat([argv])
      return true
    }
    menu.desktopSearch.compositor = null
    menu.openRoute("root")
    t.waitFor(function () {
      return menu.rowsLoaded && menu.opened
    }, 10000, "menu opens", function () {
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      t.equal(row() ? row().desktopKey : "", "project:p-aranea", "project appears with canonical identity")
      t.equal(row() ? row().label : "", "Open Aranea", "project offers Open")
      t.check(row() && row().detail.indexOf("/tmp/dev/aranea") >= 0 && row().detail.indexOf("Workspace 7") >= 0, "project detail contains canonical location and workspace")
      t.equal(menu.recoveryLabel, "Project details", "selected project has secondary details control")
      menu.recoverSelected()
      t.equal(host.details, [["aranea", "projects", "details", "p-aranea"]], "details uses public CLI with opaque ID")
      t.equal(requests(), 0, "details submits no launch")
      menu.openRoute("root")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      menu.handleKey(key(Qt.Key_Return))
      t.equal(requests(), 1, "Enter submits exactly once")
      t.equal(JSON.parse(host.calls.filter(function (argv) {
        return argv[2] === "request"
      })[0][3]), {
        projectId: "p-aranea",
        checkoutId: "c-main"
      }, "submission retains exact checkout identity")
      t.check(menu.opened, "project request keeps menu open")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("synthetic pending main")
      chooseCheckout("c-main")
      t.equal(row().actionStatus, "pending", "synthetic pending remains attached to main")
      host.operation("observing", null)
      t.equal(row().actionStatus, "pending", "owner progress appears on row")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("owner pending main")
      menu.cancel()
      menu.openRoute("root")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      checkFeatureFeedbackAbsent("reopened feature during main launch")
      t.equal(requests(), 1, "changing checkout and reopening never resubmit main launch")
      chooseCheckout("c-main")
      t.equal(row().actionStatus, "pending", "matching main restores pending after reopen")
      menu.setFilter("app: absent")
      menu.cancel()
      menu.openRoute("root")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      t.equal(row().actionStatus, "pending", "reopen mid-launch reconnects existing progress")
      t.equal(requests(), 1, "reopen mid-launch never resubmits")
      menu.cancel()
      host.operation("completed", "partial")
      t.equal(requests(), 1, "changing query and closing never resubmit accepted work")
      menu.openRoute("root")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      t.equal(row().actionStatus, "partial", "reopen retains accepted partial feedback")
      t.check(row().actionMessage.indexOf("Terminal was not observed") >= 0, "partial shows owner feedback")
      t.check(row().detail.indexOf("Terminal was not observed") >= 0 && row().detail.indexOf("/tmp/dev/aranea") >= 0, "visible partial detail retains feedback and canonical path")
      t.check(menu.opened, "partial feedback keeps menu open")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("completed partial main")
      menu.cancel()
      menu.openRoute("root")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      checkFeatureFeedbackAbsent("reopened feature after completed main")
      chooseCheckout("c-main")
      t.equal(row().actionStatus, "partial", "matching main restores partial feedback after reopen")
      t.check(row().detail.indexOf("Terminal was not observed") >= 0, "matching main retains visible partial outcome")
      // Re-resolve selected checkout before dispatch, without waiting for publication.
      var original = JSON.parse(JSON.stringify(host.snapshot))
      client.snapshot.projects[0].checkouts = []
      host.snapshot = JSON.parse(JSON.stringify(client.snapshot))
      t.check(menu.cursorActive && row().desktopKey === "project:p-aranea", "cached project remains selected until source publication")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(requests(), 1, "vanished selected checkout refuses launch")
      t.check(menu.notice.indexOf("no longer available") >= 0, "fresh project activation reports vanished checkout")
      t.check(menu.opened, "vanished checkout keeps menu open")
      menu.desktopSearch.refreshNow()
      t.check(!menu.cursorActive && menu.selectedIndex === -1, "removed project selection clears cursor")
      menu.handleKey(key(Qt.Key_Return))
      t.equal(requests(), 1, "cleared selection cannot launch another target")
      host.snapshot = original
      client.snapshot = original
      menu.setFilter("project: other")
      menu.setFilter("project: aranea")
      menu.desktopSearch.refreshNow()
      // Owner refusal is actionable and does not leave a false pending row.
      host.refuse = true
      menu.handleKey(key(Qt.Key_Return))
      t.equal(requests(), 2, "fresh user action may submit after completed work")
      t.equal(row().actionStatus, "failed", "rejected request clears pending presentation")
      t.check(row().actionMessage.indexOf("Checkout no longer exists") >= 0, "owner refusal remains actionable on row")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("refused main request")
      chooseCheckout("c-main")
      t.equal(row().actionStatus, "failed", "matching main restores refusal feedback")
      host.refuse = false
      menu.handleKey(key(Qt.Key_Return))
      t.equal(requests(), 3, "retry is explicit after refusal")
      host.ownerGeneration = 2
      host.operation("completed", "observed")
      t.equal(row().actionStatus, "observed", "confirmed owner result remains visible")
      t.check(row().detail.indexOf("Project ready") >= 0, "visible observed detail confirms readiness")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("completed observed main")
      chooseCheckout("c-main")
      t.equal(row().actionStatus, "observed", "matching main restores observed feedback")
      host.snapshot = JSON.parse(JSON.stringify(original))
      host.snapshot.bindings = [
        {
          projectId: "p-aranea",
          checkoutId: "c-main",
          role: "editor",
          workspaceId: 7,
          address: "0xabc",
          appId: "editor",
          pid: 42,
          sessionId: "test-session",
          evidence: {
            processVerified: true,
            mode: "process-app-id"
          }
        }
      ]
      client.snapshot = host.snapshot
      t.equal(row().label, "Resume Aranea", "proven current-session project offers Resume")
      var newer = {
        id: "newer",
        projectId: "p-aranea",
        checkoutId: "c-main",
        sessionId: "test-session",
        generation: 4,
        state: "completed",
        outcome: "observed",
        steps: []
      }
      menu.desktopSearch.projectOperationChanged(newer)
      menu.desktopSearch.projectOperationChanged(Object.assign({}, newer, {
        id: "older",
        generation: 3,
        outcome: "partial"
      }))
      t.equal(row().actionStatus, "observed", "older same-checkout generation cannot overwrite newer result")
      menu.desktopSearch.projectOperationChanged(Object.assign({}, newer, {
        state: "observing",
        outcome: null
      }))
      t.equal(row().actionStatus, "observed", "delayed progress cannot overwrite terminal outcome of same generation")
      client.error = "Late submission refusal"
      t.equal(row().actionStatus, "observed", "late local refusal cannot overwrite newer accepted result")
      client.error = ""
      host.snapshot = Object.assign({}, host.snapshot, {
        sessionId: "next-session",
        operations: [],
        bindings: []
      })
      client.snapshot = host.snapshot
      t.equal(row().actionStatus, "", "empty new owner session clears historical project readiness")
      menu.desktopSearch.projectOperationChanged(newer)
      t.equal(row().actionStatus, "", "old-session callback cannot restore historical feedback")
      host.readiness = true
      client.readyTimeout = 40
      client.pollInterval = 10
      menu.handleKey(key(Qt.Key_Return))
      t.equal(row().actionStatus, "pending", "rejected readiness alone keeps preparation pending")
      chooseCheckout("c-feature")
      checkFeatureFeedbackAbsent("main readiness preparation")
      t.waitFor(function () {
        return !client.pending
      }, 1000, "readiness preparation has bounded deadline", function () {
        checkFeatureFeedbackAbsent("main readiness deadline after checkout change")
        chooseCheckout("c-main")
        t.equal(row().actionStatus, "failed", "readiness deadline clears pending feedback")
        t.check(row().actionMessage.indexOf("Owner is preparing") >= 0, "readiness refusal exposes recovery message")
        var beforeCapture = requests()
        menu.desktopActions.beginShowcase({
          notifications: {
            available: false
          },
          audio: {
            available: false
          },
          wallpaper: {
            available: false
          }
        }, {})
        // Capture binding may be replaced above by test setup; explicitly set inert first.
        client.captureActive = true
        menu.handleKey(key(Qt.Key_Return))
        menu.recoverSelected()
        t.equal(requests(), beforeCapture, "capture refuses project submission")
        t.equal(host.details.length, 1, "capture refuses details dispatch")
        t.done()
      })
    })
  }
}
