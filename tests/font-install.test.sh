#!/usr/bin/env bash
# Bundled fonts install without altering preferences or unrelated user fonts.
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
mkdir -p "$XDG_CONFIG_HOME/aranea" "$XDG_DATA_HOME/fonts"
printf '{"uiFamily":"Example Sans","technicalFamily":"Example Mono"}' >"$XDG_CONFIG_HOME/aranea/fonts.json"
cp "$XDG_CONFIG_HOME/aranea/fonts.json" "$ARANEA_TEST_SANDBOX/preferences"
printf untouched >"$XDG_DATA_HOME/fonts/user-font.ttf"
"$repo_root/scripts/install-fonts"
target="$XDG_DATA_HOME/fonts/aranea"
[[ "$(fc-scan --format '%{family[0]}' "$target/ibm-plex-sans/IBMPlexSans-Regular.ttf")" == 'IBM Plex Sans' ]]
[[ "$(fc-scan --format '%{family[0]}' "$target/source-sans-3/SourceSans3-Regular.ttf")" == 'Source Sans 3' ]]
[[ "$(fc-scan --format '%{family[0]}' "$target/inter/Inter-Regular.ttf")" == 'Inter' ]]
[[ "$(fc-scan --format '%{family[0]}' "$target/inter/InterDisplay-Regular.ttf")" == 'Inter Display' ]]
[[ "$(fc-scan --format '%{family[0]}' "$target/jetbrains-mono/JetBrainsMono-Regular.ttf")" == 'JetBrains Mono' ]]
[[ "$(fc-scan --format '%{family[0]}' "$target/jetbrains-mono/JetBrainsMonoNL-Regular.ttf")" == 'JetBrains Mono NL' ]]
cmp "$repo_root/fonts/ibm-plex-sans/OFL.txt" "$target/ibm-plex-sans/OFL.txt"
cmp "$repo_root/fonts/source-sans-3/OFL.txt" "$target/source-sans-3/OFL.txt"
for source in "$repo_root/fonts/"*/*.ttf "$repo_root/fonts/"*/*.txt; do
  cmp "$source" "$target/${source#"$repo_root/fonts/"}"
done
cmp "$XDG_CONFIG_HOME/aranea/fonts.json" "$ARANEA_TEST_SANDBOX/preferences"
[[ "$(cat "$XDG_DATA_HOME/fonts/user-font.ttf")" == untouched ]]
# An unchanged second install must not rewrite font files.
touch -t 200001010000 "$target/ibm-plex-sans/IBMPlexSans-Regular.ttf"
before="$(stat -c %Y "$target/ibm-plex-sans/IBMPlexSans-Regular.ttf")"
"$repo_root/scripts/install-fonts"
[[ "$(stat -c %Y "$target/ibm-plex-sans/IBMPlexSans-Regular.ttf")" == "$before" ]]
# A damaged copy is repaired from the shipped font on the next activation.
printf damaged >"$target/ibm-plex-sans/IBMPlexSans-Regular.ttf"
"$repo_root/scripts/install-fonts"
cmp "$repo_root/fonts/ibm-plex-sans/IBMPlexSans-Regular.ttf" "$target/ibm-plex-sans/IBMPlexSans-Regular.ttf"
echo 'bundled font installation passed'
