# Rebranding guide

Aranea is designed so a theme fork can change its visible identity from a
small set of source files. Edit the sources, regenerate the projections, and
do not edit generated assets by hand.

## The three customization sources

| Source                              | Change it to update                                                                |
| ----------------------------------- | ---------------------------------------------------------------------------------- |
| `design/brand.toml`                 | Product name, short name, tagline, palette label, lock subtitle, and ceremony copy |
| `design/tokens.toml`                | Colors, shell surfaces, dimensions, motion, and integration values                 |
| `branding/marks/aranea-primary.svg` | The canonical brand mark used across the desktop                                   |

The primary SVG should keep its existing SVG structure (one gradient-filled
path in a padded square viewBox) and its three semantic mark colors:
`#8af79c`, `#2cf2b8` and `#00e5ff` for the gradient stops. Those colors are
projected to `mark_start`, `mark_mid` and `mark_end` from
`design/tokens.toml`. If the replacement SVG introduces different source
colors, update the projection map in `tools/token-generator.mjs` as part of
the same change. Keep some padding inside the viewBox: the generator also
insets the mark when it renders the 640x640 `unlock.png`, so the spider never
touches the edge of the boot screen.

## Make a rebrand

1. Edit `design/brand.toml`.
2. Replace `branding/marks/aranea-primary.svg` with the new source mark.
3. Edit the colors in `design/tokens.toml`.
4. Regenerate every committed projection:

   ```bash
   scripts/generate-tokens --write
   scripts/generate-tokens --check
   ```

5. Run the focused contract checks:

   ```bash
   bash tests/branding.test.sh
   bash tests/tokens.test.sh
   bash tests/application-integrations.test.sh
   ```

The generator updates the shared QML brand config, browser/session CSS,
branding text, shell-readable `branding/brand.env`, the `unlock.png` boot
logo, motifs, status glyphs, icon projections,
cursor integrations, and platform theme files.

## What happens at boot and lock screen

The same generated mark and palette drive both screens:

- the lock screen (`plugins/araneadev.lock`) draws the generated brand mark,
  the brand name and lock subtitle from `design/brand.toml` and the palette
  directly, so it follows a rebrand with no extra artwork;
- `unlock.png` is the boot logo: Omarchy's Plymouth theme draws it centred,
  on the `colors.toml` background, with the password entry tinted in the
  foreground colour below it.

The README screenshots of both screens are real renders of these
(`tools/render-lock-preview` and `tools/render-plymouth-preview`, run by
`scripts/capture-screenshots --surface lock` and `--surface plymouth`), so
they follow a rebrand when they are recaptured.

Plymouth activation is still an Omarchy operation after installation:

```bash
omarchy plymouth set-by-theme aranea
```

The generator creates the logo; it does not replace Plymouth's boot
animation or system activation step.

## Generated files and templates

Generated outputs include the files under `branding/`, `colors.toml`,
`shell.toml`, integration stylesheets, platform configs, shared QML config,
and raster artwork. They are checked into the repository for installation and
must not be edited directly.

If the shape or semantic role of a motif or status glyph needs to change, edit
the corresponding template under `design/templates/assets/branding/` and run
the generator again. If an integration needs a new token, add it to
`design/tokens.toml`, expose it through the appropriate generated projection,
and add a contract test before regenerating outputs.

## Final verification

For the complete contributor verification workflow, including QML, JavaScript,
ShellCheck, documentation, and screenshot checks, see
[Development](development.md). The public README intentionally omits those
development-only commands and capture details.
