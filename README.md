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

`backgrounds/background-4k.png` — a true 4K (3840×2160) render of the site's
hero gradient — mint/violet aurora glow, dot-grid constellation lines, film
grain — with the AraneaDev logo centered.

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

## Beyond the terminal

Omarchy templates most terminal- and app-color config straight from
`colors.toml` (Alacritty, Foot, Ghostty, Kitty, btop, the Omarchy shell's bar
and notifications, Hyprland's active/inactive border gradient, even RGB
keyboard backlight). A few surfaces aren't covered by that templating, so
this theme ships them directly:

- **GTK3/GTK4 + libadwaita apps** (Nautilus, file pickers, etc.) — `gtk.css`
  remaps the Adwaita accent/surface/dialog colors to the palette above.
- **`cava`** audio visualizer — `cava-theme` gives it a mint → violet gradient
  matching the logo.
- **`conky`** system monitor — `conky.conf` draws CPU/load, memory, swap,
  disk, network, CPU+GPU temps, top processes, and battery in the same
  palette, as a native Wayland layer-shell surface pinned to the top-right
  corner (always below every app window — never a floating XWayland window
  fighting for stacking order). Requires a conky build with real
  `wlr-layer-shell` support (`out_to_wayland = true`); the stock Arch `conky`
  package doesn't compile that in — see `conky-cairo-wayland-git` on the AUR.

  ![Conky preview](preview-conky.png)

None of these are wired up by Omarchy automatically; symlink them in so they
keep following the theme on every `omarchy theme set`:

```bash
mkdir -p ~/.config/gtk-4.0 ~/.config/gtk-3.0 ~/.config/cava ~/.config/conky
ln -nsf ~/.local/state/omarchy/current/theme/gtk.css ~/.config/gtk-4.0/gtk.css
ln -nsf ~/.local/state/omarchy/current/theme/gtk.css ~/.config/gtk-3.0/gtk.css
ln -nsf ~/.local/state/omarchy/current/theme/cava-theme ~/.config/cava/config
ln -nsf ~/.local/state/omarchy/current/theme/conky.conf ~/.config/conky/conky.conf
```

Autostart conky itself from `~/.config/hypr/autostart.lua`:

```lua
o.launch_on_start("conky -c ~/.config/conky/conky.conf")
```

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
