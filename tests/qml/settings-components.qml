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
        entries: [
          {
            time: '06:00',
            wallpaper: 'day'
          },
          {
            time: '20:00',
            wallpaper: 'night'
          }
        ],
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
    var chooser = t.findChild(schedule, 'scheduleWallpaper:1')
    t.check(chooser && chooser.text === 'Day', 'entry selector shows catalog image title')
    chooser.activate()
    var nightChoice = t.findChild(schedule, 'scheduleChoice:1:night')
    var missingChoice = t.findChild(schedule, 'scheduleChoice:1:missing')
    t.check(nightChoice && nightChoice.enabled && missingChoice && !missingChoice.enabled, 'gallery permits available images only')
    nightChoice.activate()
    t.equal(schedule.draft[0].wallpaper, 'night', 'thumbnail choice edits local entry image')
    t.equal(root.requests, before, 'wallpaper choice does not invoke owner')
    schedule.discardDraft()
    schedule.setDraft(0, '20:00')
    schedule.save()
    t.equal(root.requests, before, 'duplicate schedule times block mutation')
    t.check(!!schedule.validation.message, 'invalid schedule explains how to fix')
    var timeField = t.findChild(schedule, 'scheduleTime:1')
    schedule.setDraft(0, '07:00')
    t.check(t.findChild(schedule, 'scheduleTime:1') === timeField, 'clock edit retains the same focusable field')
    schedule.visible = false
    var updated = JSON.parse(JSON.stringify(root.state))
    updated.schedule.entries[0].time = '05:00'
    root.state = updated
    schedule.visible = true
    t.equal(schedule.draft[0].time, '07:00', 'unrelated refresh and navigation preserve dirty schedule draft')
    schedule.save()
    t.equal(root.last, ['configure schedule', ['[{"time":"07:00","wallpaper":"day"},{"time":"20:00","wallpaper":"night"}]']], 'Save submits literal daily entry JSON')
    var submitted = root.last[1]
    schedule.acceptSaved(submitted)
    t.check(schedule.dirty, 'unconfirmed save keeps draft dirty')
    updated.schedule.entries[0].time = '07:00'
    root.state = JSON.parse(JSON.stringify(updated))
    schedule.setDraft(0, '07:30')
    schedule.acceptSaved(submitted)
    t.check(schedule.dirty && schedule.draft[0].time === '07:30', 'earlier save acknowledgement preserves newer local edit')
    schedule.setDraft(0, '07:00')
    schedule.acceptSaved(submitted)
    t.check(!schedule.dirty, 'confirmed saved draft becomes clean')
    updated.schedule.entries[0].time = '05:00'
    root.state = JSON.parse(JSON.stringify(updated))
    t.equal(schedule.draft[0].time, '05:00', 'external edits refresh a clean draft after Save')
    schedule.setDraft(0, 'missing', 'wallpaper')
    before = root.requests
    schedule.save()
    t.equal(root.requests, before, 'unavailable image prevents save')
    schedule.discardDraft()
    schedule.removeEntry(1)
    schedule.removeEntry(0)
    t.equal(schedule.draft.length, 1, 'removal retains at least one daily entry')
    t.check(schedule.validation.ok, 'single available image schedule is valid')
    schedule.save()
    t.equal(JSON.parse(root.last[1][0]), [
      {
        time: '05:00',
        wallpaper: 'day'
      }
    ], 'single-entry schedule saves exact image and time')
    for (var i = 0; i < 5; i++) {
      schedule.addEntry()
      schedule.setDraft(i + 1, ['23:00', '04:00', '12:00', '09:00', '18:00'][i])
    }
    t.equal(schedule.draft.length, 6, 'Add has no four-row limit')
    schedule.save()
    t.equal(JSON.parse(root.last[1][0]).map(function (e) {
      return e.time
    }), ['04:00', '05:00', '09:00', '12:00', '18:00', '23:00'], 'Save sorts arbitrary daily entries')
    t.check(root.state.schedule.enabled === false, 'Save keeps enabled choice unchanged')
    before = root.requests
    var retained = JSON.stringify(schedule.draft)
    schedule.displayOnly = true
    schedule.setDraft(0, '10:00')
    schedule.addEntry()
    schedule.removeEntry(0)
    schedule.discardDraft()
    schedule.save()
    t.equal(JSON.stringify(schedule.draft), retained, 'display-only blocks every draft mutation')
    t.equal(root.requests, before, 'display-only sends no schedule requests')
    schedule.displayOnly = false
    schedule.pending = true
    schedule.setDraft(0, '10:00')
    schedule.addEntry()
    schedule.removeEntry(0)
    schedule.discardDraft()
    schedule.save()
    t.equal(JSON.stringify(schedule.draft), retained, 'pending blocks every draft mutation')
    t.equal(root.requests, before, 'pending sends no schedule requests')
    t.check(!t.findChild(schedule, 'scheduleAdd').enabled && !t.findChild(schedule, 'scheduleTime:1').enabled && !t.findChild(schedule, 'scheduleWallpaper:1').enabled, 'pending disables Add, clock and wallpaper UI')
    schedule.pending = false
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
