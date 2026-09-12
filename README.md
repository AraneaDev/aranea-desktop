# Aranea

An [Omarchy](https://omarchy.org) theme forked from the stock `hackerman` theme,
recolored to match [tim-schipper.nl](https://tim-schipper.nl)'s exact palette,
with an "AraneaDev" wordmark (set in [UnifrakturCook](https://fonts.google.com/specimen/UnifrakturCook),
a bold gothic blackletter) used as the logo, idle screensaver, and Plymouth
boot-screen badge.

## Palette

| Role              | Hex       |
|-------------------|-----------|
| Background        | `#08090b` |
| Accent (mint)      | `#3bff9e` |
| Accent 2 (violet)  | `#7a5cff` |
| Foreground         | `#e7ecf3` |
| Muted foreground   | `#8b96a6` |

## Wallpaper

`backgrounds/hero.jpg` reproduces the site's actual hero background: the same
radial gradient, a soft mint/violet aurora glow, a faint dot grid, and film
grain.

## Install

```bash
omarchy theme install <this-repo-url>
omarchy theme set aranea
```

To also use the AraneaDev wordmark as your fastfetch logo, idle screensaver,
and Plymouth boot screen (these are global Omarchy branding, not part of the
theme package itself):

```bash
cp branding/about.txt branding/screensaver.txt ~/.config/omarchy/branding/
omarchy plymouth set by theme aranea
```

The fastfetch logo is two-tone (mint "Aranea" / violet "Dev") via fastfetch's
`$1`/`$2` color placeholders — set `"color": { "1": "#3bff9e", "2": "#7a5cff" }`
on the logo in your `~/.config/fastfetch/config.jsonc` to match.
