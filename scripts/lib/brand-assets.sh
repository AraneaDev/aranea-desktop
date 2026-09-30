#!/usr/bin/env bash
# Finds branding files that Aranea's plugins reference but the active theme
# lacks: the mark named by BrandConfig's markFile and every literal
# brandingMarksPath/brandingMotifsPath/brandingGlyphsPath + "file" path. A
# plugin deploy newer than the installed theme leaves such gaps (a blank
# mark). Sourced, not run.

# Prints each branding file (relative to THEME_ROOT, e.g. branding/brand.svg)
# referenced by the plugins in PLUGIN_ROOT that THEME_ROOT does not have, one
# per line; prints nothing when PLUGIN_ROOT has no araneadev.shared plugin.
missing_brand_assets() {
  local plugin_root="$1" theme_root="$2" config mark kind file
  config="$plugin_root/araneadev.shared/BrandConfig.qml"
  [[ -f "$config" ]] || return 0
  {
    mark="$(sed -nE 's/.*property string markFile: "([^"]+)".*/\1/p' "$config" | head -n1)"
    [[ -n "$mark" ]] && printf 'branding/%s\n' "$mark"
    grep -rhoE 'branding(Marks|Motifs|Glyphs)Path \+ "[^"]+"' "$plugin_root" --include='*.qml' |
      while IFS= read -r ref; do
        kind="$(sed -E 's/^branding([A-Za-z]+)Path.*/\1/' <<<"$ref" | tr '[:upper:]' '[:lower:]')"
        file="$(sed -E 's/.*"([^"]+)"$/\1/' <<<"$ref")"
        printf 'branding/%s/%s\n' "$kind" "$file"
      done
  } | sort -u | while IFS= read -r asset; do
    [[ -e "$theme_root/$asset" ]] || printf '%s\n' "$asset"
  done
}
