// Persistent default-device selection: observed outcomes, exact identity and leases.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.audio" as Audio

ShellRoot {
  id: host
  // Exact default requests reaching the injected PipeWire dispatch boundary.
  property var sent: []
  // Search outcomes, keyed by request identity rather than device position.
  property var completed: []
  // Complete node identities; no real audio device is contacted.
  property var speakers: ({
      id: 7,
      name: "speaker",
      description: "Desk Speakers",
      isSink: true,
      isStream: false,
      audio: ({})
    })
  // Second device used to exercise queuing and identity reuse.
  property var headphones: ({
      id: 8,
      name: "headphones",
      description: "Headphones",
      isSink: true,
      isStream: false,
      audio: ({})
    })
  QmlTest {
    id: t
  }
  QtObject {
    id: backend
    property var nodes: ({
        values: [host.speakers, host.headphones]
      })
    property var defaultAudioSink: host.headphones
    property var defaultAudioSource: null
  }
  Audio.AudioDefaults {
    id: owner
    backend: backend
    observationsEnabled: false
    confirmationTimeout: 80
    sinkAvailabilityLoaded: true
    sinkAvailability: ({
        speaker: true,
        headphones: true
      })
    sendDefault: function (channel, node) {
      host.sent = host.sent.concat([[channel, node.id, node.name]])
    }
    onOutputCompleted: function (id, ok, message) {
      host.completed = host.completed.concat([[id, ok, message]])
    }
  }
  Component.onCompleted: {
    t.equal(owner.snapshot().outputs.map(function (row) {
      return row.key
    }), ["7:speaker", "8:headphones"], "fresh device identities exposed")
    t.check(owner.requestOutput("8:headphones", "current"), "current device is an accepted no-op")
    t.equal(host.sent.length, 0, "current output is not sent again from search")
    t.equal(host.completed[0], ["current", true, ""], "no-op confirms current state")
    t.check(owner.requestOutput("7:speaker", "first"), "fresh output request accepted")
    t.equal(host.sent[0], ["output", 7, "speaker"], "exact output identity dispatched")
    t.check(owner.snapshot().busy, "dispatch alone remains pending")
    t.check(!owner.requestOutput("8:headphones", "busy"), "second search request refused while busy")
    owner.panelOpened()
    owner.panelOpened()
    owner.acquireSearch()
    owner.panelClosed()
    owner.panelClosed()
    owner.releaseSearch()
    t.check(owner.snapshot().busy, "closing consumers does not cancel submitted search request")
    backend.defaultAudioSink = host.speakers
    t.step(10, function () {
      t.equal(host.completed[1], ["first", true, ""], "observed PipeWire default confirms exact request")
      t.check(!owner.snapshot().busy, "confirmed request settles")
      t.check(owner.requestOutput("8:headphones", "timeout"), "next output starts")
      owner.requestDefault("output", host.speakers)
      t.equal(owner.outputPending.queued, "7:speaker", "panel still queues its last device choice")
      t.step(110, function () {
        t.check(!owner.snapshot().busy, "timeout falls back to observed default")
        t.equal(host.completed[2][0], "timeout", "timeout belongs to original request")
        t.check(!host.completed[2][1], "missing echo fails search request")
        t.equal(host.sent.length, 2, "timed-out request never sends queued panel choice")
        backend.nodes = {
          values: [
            {
              id: 8,
              name: "replacement",
              description: "Replacement",
              isSink: true,
              isStream: false,
              audio: ({})
            }
          ]
        }
        backend.defaultAudioSink = null
        t.step(10, function () {
          t.check(!owner.requestOutput("8:headphones", "reused"), "reused node id cannot select a different device")
          t.check(!owner.requestOutput("7:speaker", "cached"), "cached display node cannot be dispatched after removal")
          owner.sinkAvailability = {
            replacement: false
          }
          t.check(!owner.requestOutput("8:replacement", "unplugged"), "unavailable output refused")
          t.equal(owner.snapshot().outputs.length, 0, "search omits unavailable outputs")
          owner.sinkAvailability = {
            replacement: true
          }
          t.check(owner.requestOutput("8:replacement", "removed"), "replacement request starts")
          backend.nodes = {
            values: []
          }
          t.step(10, function () {
            t.equal(host.completed[3][0], "removed", "removed device settles original request")
            t.check(!host.completed[3][1], "removed device fails instead of selecting another")
            t.check(!owner.snapshot().busy, "removed request clears pending")
            t.done()
          })
        })
      })
    })
  }
}
