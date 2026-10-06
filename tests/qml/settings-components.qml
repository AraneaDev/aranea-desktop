// Real page, keyboard, selection, draft and responsive-content behavior.
import QtQuick
import Quickshell
import "lib"
import "plugins/araneadev.settings" as Settings

ShellRoot {
  id: root
  // Number of mutation requests emitted by the real pages.
  property int requests: 0
  // Latest operation and arguments emitted by a page.
  property var last: []
  // Latest adapter snapshot; unreadable sections are never replaced with defaults.
  property var state: ({
      motion: {
        configured: 'on',
        applied: 'on',
        availability: 'available'
      },
      wallpaper: {
        activeId: 'day',
        availability: 'available'
      },
      wallpapers: [
        {
          id: 'day',
          label: 'Day',
          path: '',
          available: true
        },
        {
          id: 'night',
          label: 'Night',
          path: '',
          available: true
        },
        {
          id: 'missing',
          label: 'Missing',
          path: '',
          available: false
        }
      ],
      wallpapersAvailability: 'available',
      schedule: {
        enabled: false,
        applied: false,
        availability: 'available',
        dawn: '06:00',
        day: '08:00',
        dusk: '18:00',
        night: '20:00'
      },
      integrations: [
        {
          id: 'session',
          status: 'inactive',
          availability: 'available'
        },
        {
          id: 'missing',
          status: 'inactive',
          availability: 'unavailable'
        }
      ],
      integrationsAvailability: 'available'
    })
  QmlTest {
    id: t
  }
  Settings.AppearancePage {
    id: appearance
    width: 560
    backendState: root.state
    onRequest: function (operation, args) {
      root.requests++
      root.last = [operation, args]
    }
  }
  Settings.SchedulePage {
    id: schedule
    width: 560
    backendState: root.state
    onRequest: function (operation, args) {
      root.requests++
      root.last = [operation, args]
    }
  }
  Settings.IntegrationsPage {
    id: integrations
    width: 560
    backendState: root.state
    onRequest: function (operation, args) {
      root.requests++
      root.last = [operation, args]
    }
  }
  Settings.NotificationsPage {
    id: notifications
    width: 560
    notifications: ({
        dnd: null,
        dndAvailability: 'unavailable',
        quiet: 'scheduled',
        quietAvailability: 'available',
        window: '22:00-07:00',
        windowAvailability: 'available'
      })
    onRequest: root.requests++
  }
  Settings.SettingsNavigation {
    id: navigation
    onSectionRequested: function (section) {
      selectedSection = section
    }
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {}
  }
  Settings.SettingsSurface {
    id: window
    root: entry
    width: 652
    height: 452
  }
  // Find user-visible text through the real page tree.
  function hasText(item, text) {
    if (item.text !== undefined && item.text === text)
      return true
    var kids = t.childrenOf(item)
    for (var i = 0; i < kids.length; i++)
      if (hasText(kids[i], text))
        return true
    return false
  }
  Component.onCompleted: t.step(20, function () {
    t.check(window.compact, 'narrow screen uses category selector above content')
    window.width = 840
    t.check(!window.compact, 'wide surface uses side navigation')
    window.width = 652
    t.equal(t.findChild(appearance, 'wallpaperCurrentName').text, 'Day', 'appearance renders owner wallpaper identity')
    appearance.selectWallpaper('night')
    navigation.choose('notifications')
    t.equal(root.requests, 0, 'thumbnail and category selection issue zero mutations')
    t.equal(appearance.selectedId, 'night', 'wallpaper has local selected state')
    t.equal(appearance.appliedId, 'day', 'wallpaper selected and owner applied states differ')
    appearance.applyWallpaper()
    t.equal(root.last, ['set wallpaper', ['night']], 'Apply uses stable wallpaper ID')
    appearance.selectWallpaper('missing')
    var before = root.requests
    appearance.applyWallpaper()
    t.equal(root.requests, before, 'unavailable wallpaper cannot Apply')
    schedule.setDraft(0, '09:00')
    schedule.save()
    t.equal(root.requests, before, 'invalid schedule blocks mutation')
    t.check(!!schedule.validation.message, 'invalid schedule explains how to fix')
    schedule.setDraft(0, '07:00')
    schedule.visible = false
    var updated = JSON.parse(JSON.stringify(root.state))
    updated.schedule.dawn = '05:00'
    root.state = updated
    schedule.visible = true
    t.equal(schedule.draft[0], '07:00', 'unrelated refresh and navigation preserve dirty schedule draft')
    schedule.save()
    t.equal(root.last, ['configure schedule', ['07:00', '08:00', '18:00', '20:00']], 'Save submits draft phase values explicitly')
    schedule.acceptSaved(['07:00', '08:00', '18:00', '20:00'])
    t.check(schedule.dirty, 'unconfirmed save keeps draft dirty')
    updated.schedule.dawn = '07:00'
    root.state = JSON.parse(JSON.stringify(updated))
    schedule.acceptSaved(['07:00', '08:00', '18:00', '20:00'])
    t.check(!schedule.dirty, 'confirmed saved draft becomes clean')
    updated.schedule.dawn = '05:00'
    root.state = JSON.parse(JSON.stringify(updated))
    t.equal(schedule.draft[0], '05:00', 'external edits refresh a clean draft after Save')
    t.check(!t.findChild(notifications, 'dndToggle').enabled, 'unavailable DND control disabled')
    t.equal(notifications.quietDescription, 'Scheduled', 'quiet-hours effective state is read-only')
    t.equal(notifications.windowDescription, '22:00-07:00', 'configured quiet window is visible')
    var buttons = t.findChildren(integrations, 'integrationAction')
    t.check(buttons[0].enabled && !buttons[1].enabled, 'only unavailable integration is disabled')
    before = root.requests
    buttons[1].activate()
    t.equal(root.requests, before, 'disabled integration cannot activate through keyboard path')
    var event = {
      key: Qt.Key_Escape,
      accepted: false
    }
    entry.opened = true
    window.handleKey(event)
    t.check(!entry.opened && event.accepted, 'Escape closes dedicated surface')
    integrations.pending = true
    t.check(!buttons[0].enabled, 'competing integration mutations disabled')
    t.done()
  })
}
