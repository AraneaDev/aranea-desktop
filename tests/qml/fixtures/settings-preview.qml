// Inert offscreen host of the production settings content, never the desktop.
import QtQuick
import Quickshell
import qs.Commons
import "plugins/araneadev.settings" as Settings
import "ProjectPreview.js" as ProjectPreview

ShellRoot {
  id: harness
  // Capture variant supplied by the renderer.
  readonly property string fixture: Quickshell.env('ARANEA_SETTINGS_RENDER_FIXTURE')
  // Repository artwork, independent of live preferences.
  readonly property string artwork: Quickshell.env('ARANEA_SETTINGS_RENDER_ROOT') + '/backgrounds/'
  // Wait for images and fonts before grabbing.
  property int polls: 0
  // Font overrides apply after the theme singleton finishes loading.
  property bool fontPrepared: false
  // Scroll detail/recovery captures after the actual production layout settles.
  property bool positioned: false
  // Report the offscreen render outcome to the parent process.
  function finish(ok, message) {
    console.log((ok ? 'SETTINGSRENDER OK ' : 'SETTINGSRENDER FAIL ') + message)
    Qt.quit()
  }
  // Visit actual content objects, including Flickable content.
  function collect(item, out) {
    var kids = item.data || item.children || []
    for (var i = 0; i < kids.length; i++) {
      out.push(kids[i])
      collect(kids[i], out)
    }
    if (item.contentItem && kids.indexOf(item.contentItem) < 0)
      collect(item.contentItem, out)
    return out
  }
  Settings.Settings {
    id: entry
    windowEnabled: false
    runner: function (argv, done) {
      harness.finish(false, 'unexpected process request: ' + argv[0])
    }
  }
  FloatingWindow {
    implicitWidth: Number(Quickshell.env('ARANEA_SETTINGS_RENDER_WIDTH'))
    implicitHeight: Number(Quickshell.env('ARANEA_SETTINGS_RENDER_HEIGHT'))
    color: 'transparent'
    visible: true
    Settings.SettingsSurface {
      id: surface
      anchors.fill: parent
      root: entry
    }
  }
  Component.onCompleted: {
    Style.spacingScale = 1
    Style.spacingScaleWithFont = false
    entry.view = surface
    entry.projectController.runner = function (argv, done) {
      harness.finish(false, 'unexpected registry process')
    }
    entry.projectClient.runner = function (argv, done) {
      harness.finish(false, 'unexpected project owner process')
    }
    entry.discoveryClient.runner = function (argv) {
      harness.finish(false, 'unexpected scan process')
    }
    var state = {
      display: {
        monitor: 'eDP-1',
        scale: 2,
        width: 3840,
        height: 2160,
        availability: 'available',
        persistenceSupport: 'supported',
        configuredScale: 2
      },
      motion: {
        configured: 'on',
        applied: 'on',
        application: 'applied',
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
          path: artwork + 'background-day.png',
          available: true
        },
        {
          id: 'night',
          label: 'Night',
          path: artwork + 'background-night.png',
          available: true
        }
      ],
      wallpapersAvailability: 'available',
      fonts: {
        uiFamily: 'Inter',
        technicalFamily: 'JetBrains Mono',
        families: ['Inter', 'IBM Plex Sans', 'Source Sans 3', 'JetBrains Mono'],
        monospaceFamilies: ['JetBrains Mono', 'JetBrains Mono NL'],
        availability: 'available'
      },
      schedule: {
        enabled: true,
        applied: true,
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
          id: 'terminal',
          status: 'active',
          availability: 'available'
        }
      ],
      integrationsAvailability: 'available'
    }
    var sample = {
      state: state,
      notifications: {
        dnd: 'off',
        dndAvailability: 'available',
        quiet: 'scheduled',
        quietAvailability: 'available',
        window: '22:00-07:00',
        windowAvailability: 'available'
      },
      results: {},
      itemErrors: {}
    }
    var section = 'appearance'
    if (fixture === 'scaling') {
      section = 'display'
      state.display.scale = 2.666667
      state.display.configuredScale = 2.66667
      sample.results['display-scale'] = 'Applied · 2.666667 · saved'
    }
    if (fixture === 'dirty' || fixture === 'narrow')
      section = 'schedule'
    else if (fixture === 'integration-failed') {
      section = 'integrations'
      sample.results['integration:session'] = 'Failed'
      sample.itemErrors['integration:session'] = 'Could not activate session styling. Your existing files were preserved. Check the helper diagnostic, then retry.'
    } else if (fixture === 'notifications')
      section = 'notifications'
    else if (fixture === 'unavailable') {
      sample.state = {}
      sample.error = 'Desktop settings are unavailable. Check that the settings helper is installed, then Retry.'
    }
    if (fixture.indexOf('projects-') === 0 || fixture.indexOf('project-') === 0) {
      var projects = ProjectPreview.sample(fixture, Quickshell.env('ARANEA_PROJECT_RENDER_STATE'))
      Object.keys(projects).forEach(function (key) {
        sample[key] = projects[key]
      })
      var detailsId = fixture === 'project-details' || fixture === 'project-launch-partial' ? projects.projectId : ''
      if (entry.captureBegin(JSON.stringify({
        snapshot: entry.captureSnapshot(),
        section: 'projects',
        projectId: detailsId,
        fixture: sample
      })) !== 'ok')
        finish(false, 'project fixture refused')
      return
    }
    if (entry.showcase(JSON.stringify(sample)) !== 'ok') {
      finish(false, 'fixture refused')
      return
    }
    entry.open(JSON.stringify({
      section: section
    }))
    if (fixture === 'dirty' || fixture === 'scaling') {
      var objects = collect(surface, [])
      for (var i = 0; i < objects.length; i++)
        if (fixture === 'scaling' && typeof objects[i].setScaleDraft === 'function')
          objects[i].setScaleDraft('2.667')
        else if (fixture === 'dirty' && typeof objects[i].setDraft === 'function')
          objects[i].setDraft(0, '07:00')
    }
  }
  Timer {
    interval: 100
    repeat: true
    running: true
    onTriggered: {
      harness.polls++
      var objects = harness.collect(surface, [])
      if (!harness.fontPrepared && harness.polls >= 3) {
        harness.fontPrepared = true
        var fontScale = Number(Quickshell.env('ARANEA_SETTINGS_RENDER_FONT_SCALE') || 1)
        Style.fontBaseSize = Math.round(Style.fontBaseSize * fontScale)
        var fonts = Object.assign({}, Style.fontOverrides)
        Object.keys(fonts).forEach(function (key) {
          fonts[key] = Math.round(Number(fonts[key]) * fontScale)
        })
        Style.fontOverrides = fonts
      }
      if (!harness.positioned && harness.polls >= 6) {
        harness.positioned = true
        if (harness.fixture === 'project-details' || harness.fixture === 'project-launch-partial' || harness.fixture === 'project-setup-bulk') {
          for (var j = 0; j < objects.length; j++) {
            var scroll = objects[j]
            if (scroll.contentY === undefined || !scroll.contentItem || scroll.height < 100)
              continue
            var target = 0
            for (var k = 0; k < objects.length; k++) {
              if (objects[k].text === 'Customer dashboard and developer accessibility improvements' && objects[k].visible && objects[k].font && objects[k].font.bold)
                target = Math.max(target, objects[k].mapToItem(scroll.contentItem, 0, 0).y)
            }
            scroll.contentY = Quickshell.env('ARANEA_SETTINGS_RENDER_SCROLL') === 'bottom' ? Math.max(0, scroll.contentHeight - scroll.height) : Math.min(target, Math.max(0, scroll.contentHeight - scroll.height))
          }
        }
      }
      var loading = false
      for (var i = 0; i < objects.length; i++) {
        var item = objects[i]
        if (item.source === undefined || item.status === undefined || item.progress === undefined || !String(item.source))
          continue
        if (item.status === Image.Error) {
          stop()
          harness.finish(false, 'image did not load: ' + item.source)
          return
        }
        if (item.status !== Image.Ready)
          loading = true
      }
      if (!loading && harness.polls >= 10) {
        stop()
        if (!surface.grabToImage(function (result) {
          harness.finish(result.saveToFile(Quickshell.env('ARANEA_SETTINGS_RENDER_OUTPUT')), result.image.width + 'x' + result.image.height)
        }, Qt.size(surface.width, surface.height)))
          harness.finish(false, 'grabToImage refused')
      } else if (harness.polls > 300) {
        stop()
        harness.finish(false, 'images did not settle')
      }
    }
  }
}
