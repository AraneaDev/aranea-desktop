# Aranea

An [Omarchy](https://omarchy.org) theme forked from the stock `hackerman` theme,
recolored to match [tim-schipper.nl](https://tim-schipper.nl)'s exact palette,
with the **AraneaDev** spider-and-wordmark logo carried through the wallpaper,
fastfetch, idle screensaver, lock screen, and Plymouth boot screen.

![Desktop preview](preview.png)

## Palette

| Role               | Hex       |
|--------------------|-----------|
| Background         | `#08090b` |
| Accent (mint)       | `#3bff9e` |
| Accent 2 (violet)   | `#7a5cff` |
| Foreground          | `#e7ecf3` |
| Muted foreground    | `#8b96a6` |

## Wallpaper

`backgrounds/background-4k.png` is the default: a true 4K (3840×2160) render
of the site's hero gradient — mint/violet aurora glow, dot-grid constellation
lines, film grain — with the AraneaDev logo centered.

`backgrounds/hero.jpg` is the plain hero gradient without the logo, kept as a
second option (`omarchy theme bg next` cycles between the two).

## Branding

The AraneaDev spider mark replaces the theme's previous gothic-blackletter
wordmark everywhere Omarchy shows branding:

- **Fastfetch logo** (`omarchy branding about`) — `branding/about.txt`, full
  24-bit gradient ANSI art.
- **Idle screensaver** (`omarchy branding screensaver`) — `branding/screensaver.txt`,
  plain block-character art, so `ttfx`'s own effects/coloring apply cleanly on top.
- **Lock screen + Plymouth boot logo** — `unlock.png`, trimmed and transparent,
  gradient-colored:

  ![Lock screen preview](preview-unlock.png)

## Install

```bash
omarchy theme install <this-repo-url>
omarchy theme set aranea
```

To also use the AraneaDev mark as your fastfetch logo and idle screensaver
(these are global Omarchy branding, not staged automatically with the theme):

```bash
cp branding/about.txt branding/screensaver.txt ~/.config/omarchy/branding/
```

And to set it as your Plymouth boot screen (rebuilds your kernel image, needs sudo):

```bash
omarchy plymouth set-by-theme aranea
```
