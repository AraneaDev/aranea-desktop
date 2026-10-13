# Icon gallery

Aranea’s icon integration uses a compact solid glyph language with the same
mint signal color as the Command Center. Unsupported long-tail icons inherit
from the host theme instead of being replaced with inconsistent approximations.

## Grouped bar controls

The Network icon is a linked-node hub for Network, VPN, and Bluetooth. System
uses adjustment sliders for Power, Display, and Health, with a small battery cue
and optional percentage. Their tooltips name the contained controls. Both are
shared vector artwork in `plugins/araneadev.shared/BarGroupIcon.qml`, separate
from the freedesktop icon theme and Nerd Font glyphs.

The microphone badge is conditional on active recording/capture streams; the
Health shortcut is conditional on open issues or its visible alert popup. These
are status cues rather than permanent extra navigation buttons.

## Families

The shipped gallery is organized into these freedesktop icon families:

- actions: application exit, documents, edit, navigation, list and grid;
- apps: editor, preferences, file manager, terminal, and browser;
- devices: desktop, laptop, drives, removable media, and network hardware;
- mimetypes: JSON, PDF, desktop files, archives, audio, images, text, and video;
- places: home, folders, downloads, media, root, and trash;
- status: mounted, read-only, shared, and related state markers.

Browse the source gallery directly:

```text
integrations/icons/aranea/scalable/
```

Representative icons:

| Family    | Examples                                                                              |
| --------- | ------------------------------------------------------------------------------------- |
| Actions   | `application-exit`, `document-new`, `edit-copy`, `view-refresh`                       |
| Apps      | `accessories-text-editor`, `preferences-system`, `system-file-manager`, `web-browser` |
| Devices   | `computer-laptop`, `drive-harddisk`, `network-wireless`                               |
| Mimetypes | `application-json`, `application-pdf`, `text-html`, `video-x-generic`                 |
| Places    | `folder`, `folder-download`, `go-home`, `user-trash`                                  |
| Status    | `emblem-mounted`, `emblem-readonly`, `emblem-shared`                                  |

The icon integration is installed as part of the `full` and `no_apps` profiles.
Use `scripts/aranea-integrations status` to inspect its state.
