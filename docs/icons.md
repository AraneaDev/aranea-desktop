# Icon gallery

Aranea ships three complementary icon sources: shared vectors for grouped bar
controls, a dedicated glyph font for shell labels, and a freedesktop icon theme
for applications and files. The freedesktop set uses solid mint glyphs and falls
back to `Yaru-prussiangreen-dark`, `Adwaita`, then `hicolor` for unshipped names.

## Grouped bar controls

`plugins/araneadev.shared/BarGroupIcon.qml` draws the linked-node Network hub
and System adjustment sliders. Network contains Network, VPN, and Bluetooth;
System contains Power, Display, and Health. The owning button supplies semantic
color, battery context, and tooltip text.

The microphone badge appears for active recording/capture streams. Health's
separate shortcut appears for issues or its visible alert popup. These cues
communicate current state without adding permanent destinations to the bar.

## Families

Browse [the scalable icon source](../integrations/icons/aranea/scalable/).
The theme index defines six families:

| Family    | Representative names                                                                  |
| --------- | ------------------------------------------------------------------------------------- |
| Actions   | `application-exit`, `document-new`, `edit-copy`, `view-refresh`                       |
| Apps      | `accessories-text-editor`, `preferences-system`, `system-file-manager`, `web-browser` |
| Devices   | `computer-laptop`, `drive-harddisk`, `network-wireless`                               |
| Mimetypes | `application-json`, `application-pdf`, `text-html`, `video-x-generic`                 |
| Places    | `folder`, `folder-download`, `go-home`, `user-trash`                                  |
| Status    | `emblem-mounted`, `emblem-readonly`, `emblem-shared`                                  |

The `full` and `no_apps` profiles install the icon integration. Inspect it with
`scripts/aranea-integrations status`. Font-derived geometry is owned by
`scripts/generate-font-icon-theme`; the token generator resolves the shared
accent before installation. Follow [the generation workflow](development.md#design-tokens)
instead of editing generated SVGs directly.
