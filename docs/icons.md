# Icon gallery

Aranea’s icon integration uses a compact solid glyph language with the same
mint signal color as the Command Center. Unsupported long-tail icons inherit
from the host theme instead of being replaced with inconsistent approximations.

## Families

The shipped gallery is organized into these freedesktop icon families:

- actions — application exit, documents, edit, navigation, list and grid;
- apps — editor, preferences, file manager, terminal, and browser;
- devices — desktop, laptop, drives, removable media, and network hardware;
- mimetypes — JSON, PDF, desktop files, archives, audio, images, text, and video;
- places — home, folders, downloads, media, root, and trash;
- status — mounted, read-only, shared, and related state markers.

Browse the source gallery directly:

```text
integrations/icons/aranea/scalable/
```

Representative icons:

| Family | Examples |
| --- | --- |
| Actions | `application-exit`, `document-new`, `edit-copy`, `view-refresh` |
| Apps | `accessories-text-editor`, `preferences-system`, `system-file-manager`, `web-browser` |
| Devices | `computer-laptop`, `drive-harddisk`, `network-wireless` |
| Mimetypes | `application-json`, `application-pdf`, `text-html`, `video-x-generic` |
| Places | `folder`, `folder-download`, `go-home`, `user-trash` |
| Status | `emblem-mounted`, `emblem-readonly`, `emblem-shared` |

The icon integration is installed as part of the `full` and `no_apps` profiles.
Use `scripts/aranea-integrations status` to inspect its state.
