// Real compact page drafts, explicit actions and stable Display routing.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: host
  // Requests captured from real pages without touching desktop preferences.
  property var requests: []
  QmlTest {
    id: t
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      done(0, JSON.stringify({
        schemaVersion: 1,
        ok: true,
        state: entry.controller.state
      }), '')
    }
  }
  FloatingWindow {
    implicitWidth: 840
    implicitHeight: 620
    visible: true
    Settings.SettingsSurface {
      id: surface
      root: entry
      width: 840
      height: 620
    }
  }
  Settings.Settings {
    id: freshEntry
    windowEnabled: false
    runner: function (argv, done) {}
  }
  FloatingWindow {
    implicitWidth: 432
    implicitHeight: 260
    visible: true
    Settings.SettingsSurface {
      id: freshSurface
      root: freshEntry
      width: 432
      height: 260
    }
  }
  // Locate brief owner status copy without adding a production test seam.
  function hasText(item, value) {
    if (item.text === value)
      return true
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++)
      if (hasText(kids[i], value))
        return true
    return false
  }
  // Find persistent production pages by their public draft contract.
  function pageWith(item, method) {
    if (typeof item[method] === 'function')
      return item
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++) {
      var found = pageWith(kids[i], method)
      if (found)
        return found
    }
    return null
  }
  // Locate the real shared viewport by its native Flickable properties.
  function viewport(item) {
    if (item.contentY !== undefined && item.contentHeight !== undefined)
      return item
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++) {
      var found = viewport(kids[i])
      if (found)
        return found
    }
    return null
  }
  Component.onCompleted: t.step(100, function () {
    entry.controller.state = {
      wallpaper: {
        activeId: 'day',
        availability: 'available'
      },
      wallpapersAvailability: 'available',
      wallpapers: [
        {
          id: 'day',
          label: 'Day',
          available: true
        },
        {
          id: 'night',
          label: 'Night',
          available: true
        }
      ],
      display: {
        monitor: 'eDP-1',
        width: 3840,
        height: 2160,
        scale: 2,
        availability: 'available',
        persistenceSupport: 'supported'
      }
    }
    t.check(!!t.findChild(surface, 'settingsGlyph'), 'normal header retains Settings spider identity')
    var appearance = pageWith(surface, 'selectWallpaper')
    t.equal(appearance.galleryExpanded, false, 'wallpaper gallery starts collapsed')
    t.check(!t.findChild(appearance, 'wallpaperThumbnail:night').visible, 'collapsed gallery hides selection targets')
    appearance.request.connect(function (operation, args) {
      host.requests = host.requests.concat([[operation, args]])
    })
    appearance.selectWallpaper('night')
    t.equal(requests.length, 0, 'selection only edits draft')
    if (typeof appearance.discardWallpaper === 'function') {
      appearance.discardWallpaper()
      t.equal(appearance.selectedId, appearance.appliedId, 'Discard uses observed wallpaper')
      appearance.selectWallpaper('night')
    } else
      t.check(false, 'wallpaper Discard exists')
    if (appearance.galleryExpanded !== undefined) {
      appearance.galleryExpanded = true
      appearance.galleryExpanded = false
    }
    t.equal(appearance.selectedId, 'night', 'collapse retains wallpaper draft')
    appearance.applyWallpaper()
    t.equal(requests[0], ['set wallpaper', ['night']], 'explicit Apply dispatches stable wallpaper identity')
    entry.section = 'display'
    var display = pageWith(surface, 'discardScale')
    t.check(!!display, 'Display owns scale draft and Discard')
    if (display) {
      display.request.connect(function (operation, args) {
        host.requests = host.requests.concat([[operation, args]])
      })
      t.check(hasText(display, 'Saving supported'), 'capability status never claims a pending draft is saved')
      var before = requests.length
      var presets = t.findChildren(display, 'displayScalePreset')
      t.equal(presets.length, 4, 'Display exposes four compact presets')
      presets[2].activate()
      t.equal(display.scaleDraft, '2.667', 'fractional preset keeps exact decimal')
      t.equal(requests.length, before, 'presets never apply themselves')
      display.setScaleDraft('2.667')
      display.applyScale()
      t.equal(requests[before], ['set display-scale', ['2.667']], 'exact fraction goes to existing owner')
      display.discardScale()
      t.equal(display.scaleDraft, '2', 'scale Discard restores observed scale')
      display.setScaleDraft('2.5')
      entry.section = 'appearance'
      entry.section = 'display'
      t.equal(display.scaleDraft, '2.5', 'navigation retains scale draft')
      t.equal(appearance.selectedId, 'night', 'navigation retains wallpaper draft')
    }
    surface.width = 432
    surface.height = 260
    appearance.galleryExpanded = false
    entry.section = 'appearance'
    t.step(120, function () {
      surface.layoutChangedAt = 1
      appearance.galleryExpanded = true
      t.step(120, function () {
        var scroll = viewport(surface)
        t.check(surface.layoutChangedAt > 1, 'chooser expansion rearms pointer settling gate')
        surface.scrollTo(50)
        var saved = scroll.contentY
        t.check(saved > 0, 'expanded gallery has a real scroll offset')
        entry.section = 'display'
        t.step(120, function () {
          entry.section = 'appearance'
          t.step(120, function () {
            t.equal(scroll.contentY, saved, 'navigation restores page scroll offset')
            t.check(appearance.galleryExpanded, 'navigation retains expanded chooser')
            freshEntry.controller.state = entry.controller.state
            pageWith(freshSurface, 'selectWallpaper').galleryExpanded = true
            t.step(120, function () {
              freshSurface.scrollTo(50)
              var firstOffset = viewport(freshSurface).contentY
              t.check(firstOffset > 0, 'fresh initial page has a real scroll offset')
              freshEntry.section = 'display'
              t.step(120, function () {
                freshEntry.section = 'appearance'
                t.step(120, function () {
                  t.equal(viewport(freshSurface).contentY, firstOffset, 'first navigation also restores initial page scroll offset')
                  t.done()
                })
              })
            })
          })
        })
      })
    })
  })
}
