// Wallpaper request confirmation through real controller and fake process outputs.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.menu" as Menu

ShellRoot {
  id: host
  // Current backend state, separate from command acceptance.
  property string current: "night"
  // Whether the installed manifest target remains readable.
  property bool dayAvailable: true
  // Tracked command completions, allowing delayed and failed outcomes.
  property var mutations: []
  // Accepted owner completion events.
  property var completed: []
  QmlTest {
    id: t
  }
  Menu.DesktopWallpaperActions {
    id: owner
    observationsEnabled: false
    confirmationTimeout: 80
    runner: function (argv, done) {
      if (argv[1] === "list")
        done(0, JSON.stringify([
          {
            id: "day",
            label: "Day",
            available: host.dayAvailable
          },
          {
            id: "night",
            label: "Night",
            available: true
          }
        ]), "")
      else if (argv[1] === "status")
        done(0, JSON.stringify({
          activeId: host.current,
          availability: "available"
        }), "")
      else if (argv[1] === "schedule")
        done(0, JSON.stringify({
          enabled: true,
          availability: "available"
        }), "")
      else if (argv[1] === "set")
        host.mutations = host.mutations.concat([
          {
            id: argv[2],
            done: done
          }
        ])
      else
        t.check(false, "unexpected wallpaper command")
    }
    onCompleted: function (id, ok, message) {
      host.completed = host.completed.concat([[id, ok, message]])
    }
  }
  Component.onCompleted: {
    owner.refresh()
    t.check(owner.snapshot().available, "installed catalog and backend observed")
    t.check(owner.snapshot().scheduled, "schedule context retained")
    t.check(owner.request("night", "current"), "current wallpaper is accepted")
    t.equal(host.mutations.length, 0, "current wallpaper is a no-op")
    t.equal(host.completed[0], ["current", true, ""], "current state confirms no-op")
    t.check(owner.request("day", "first"), "valid installed wallpaper accepted")
    t.equal(host.mutations[0].id, "day", "manifest id passed as exact argv")
    t.check(!owner.request("night", "busy"), "pending family rejects another request")
    owner.active = false
    host.mutations[0].done(0, "applied", "")
    t.check(owner.pending, "exit zero without observed state is not success")
    host.current = "day"
    owner.refresh()
    t.equal(host.completed[1], ["first", true, ""], "observed activeId confirms successful process")
    t.check(owner.snapshot().scheduled, "manual selection leaves schedule intact")
    host.dayAvailable = false
    t.check(owner.request("day", "vanished"), "validation request accepted")
    t.equal(host.mutations.length, 1, "fresh unavailable asset cannot run set")
    t.check(!host.completed[2][1], "vanished asset fails validation")
    host.dayAvailable = true
    t.check(owner.request("night", "failure"), "next valid target starts")
    host.mutations[1].done(1, "", "backend failure")
    t.check(!host.completed[3][1], "failed process cannot be labelled applied")
    t.check(owner.request("night", "timeout"), "retry starts after failure")
    t.step(110, function () {
      t.check(!owner.pending, "deadline clears pending request")
      t.equal(host.completed[4][0], "timeout", "deadline carries request identity")
      t.check(!host.completed[4][1], "missing completion is a failure")
      host.current = "night"
      host.mutations[2].done(0, "", "")
      t.equal(host.completed.length, 5, "late completion cannot replace timeout feedback")
      t.equal(owner.snapshot().activeId, "night", "late completion can update current observation")
      owner.showcaseActive = true
      t.check(!owner.request("day", "fixture"), "showcase refuses mutations")
      t.equal(host.mutations.length, 3, "showcase never dispatches wallpaper")
      owner.showcaseActive = false
      var reads = []
      owner.runner = function (argv, done) {
        reads.push({
          argv: argv,
          done: done
        })
      }
      owner.refresh()
      owner.refresh()
      t.equal(reads.length, 3, "read bursts coalesce without invalidating the in-flight snapshot")
      owner.request("day", "queued-validation")
      t.equal(reads.length, 3, "mutation validation waits for a fresh follow-up read")
      reads[0].done(0, JSON.stringify([
        {
          id: "day",
          label: "Day",
          available: true
        }
      ]), "")
      reads[1].done(0, JSON.stringify({
        activeId: "night",
        availability: "available"
      }), "")
      reads[2].done(0, JSON.stringify({
        enabled: true
      }), "")
      t.step(10, function () {
        t.equal(reads.length, 6, "one follow-up snapshot services the queued validation")
        reads[3].done(0, JSON.stringify([
          {
            id: "day",
            label: "Day",
            available: false
          }
        ]), "")
        reads[4].done(0, JSON.stringify({
          activeId: "night",
          availability: "available"
        }), "")
        reads[5].done(0, JSON.stringify({
          enabled: true
        }), "")
        t.check(!owner.pending, "fresh unavailable target rejects queued mutation")
        t.equal(reads.length, 6, "stale readable catalog cannot dispatch wallpaper")
        t.done()
      })
    })
  }
}
