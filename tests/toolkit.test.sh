#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"

grep -Fq 'Name=Aranea' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'Inherits=' "$repo_root/integrations/cursor/index.theme"
grep -Fq 'xcursorgen' "$repo_root/scripts/install-integration"
grep -Fq 'setcursor Aranea' "$repo_root/scripts/install-integration"
grep -Fq 'uwsm/env.d/aranea-cursor' "$repo_root/scripts/install-integration"
grep -Fq 'local/share}/icons/Aranea' "$repo_root/scripts/install-integration"
grep -Fq 'XCURSOR_THEME=Aranea' "$repo_root/integrations/cursor/uwsm-env"
grep -Fq 'HYPRCURSOR_THEME=Aranea' "$repo_root/integrations/cursor/uwsm-env"
grep -Fq 'hyprcursor-util --create' "$repo_root/scripts/install-integration"
test -f "$repo_root/integrations/cursor/hyprcursor/manifest.hl"
test -f "$repo_root/integrations/cursor/hyprcursor/hyprcursors/left_ptr/meta.hl"
for cursor in left_ptr.svg hand2.svg watch.svg crosshair.svg; do
  test -f "$repo_root/integrations/cursor/cursors/$cursor"
done
if rg -n '#ff5f56|#e6c98a' "$repo_root/integrations/cursor"; then
  echo 'cursor palette contains non-Aranea colors' >&2
  exit 1
fi
grep -Fq '<title>Aranea spider hand cursor</title>' "$repo_root/integrations/cursor/cursors/hand2.svg"
if rg -n 'circle cx="15"|circle cx="17"' "$repo_root/integrations/cursor"; then
  echo 'cursor hand artwork still contains eye dots' >&2
  exit 1
fi
grep -Fq '<title>Aranea spider pointer cursor</title>' "$repo_root/integrations/cursor/cursors/left_ptr.svg"
grep -Fq 'M5 4' "$repo_root/integrations/cursor/cursors/left_ptr.svg"
grep -Fq 'define_size = 32, watch-08.svg' "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/meta.hl"
for frame in 01 02 03 04 05 06 07 08; do
  test -f "$repo_root/integrations/cursor/cursors/watch-$frame.svg"
  test -f "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/watch-$frame.svg"
  cmp -s "$repo_root/integrations/cursor/cursors/watch-$frame.svg" \
    "$repo_root/integrations/cursor/hyprcursor/hyprcursors/watch/watch-$frame.svg"
done
for cursor in left_ptr hand2 watch crosshair; do
  cmp -s "$repo_root/integrations/cursor/cursors/$cursor.svg" \
    "$repo_root/integrations/cursor/hyprcursor/hyprcursors/$cursor/$cursor.svg"
done
grep -Fq 'BackgroundNormal=' "$repo_root/integrations/qt/kvantum/Aranea/Aranea.kvconfig"
grep -Fq 'selection' "$repo_root/gtk.css"
grep -Fq 'destructive-action' "$repo_root/gtk.css"
grep -Fq 'does not replace' "$repo_root/integrations/icons/README.md"

grep -Fq 'Name=Aranea-icons' "$repo_root/integrations/icons/aranea/index.theme"
grep -Fq 'Inherits=' "$repo_root/integrations/icons/aranea/index.theme"
grep -Fq 'Directories=scalable/places' "$repo_root/integrations/icons/aranea/index.theme"
for icon in folder.svg folder-open.svg; do
  test -f "$repo_root/integrations/icons/aranea/scalable/places/$icon"
done
grep -Fq 'icon_theme=Aranea-icons' "$repo_root/scripts/install-integration"
grep -Fq 'org.gnome.desktop.interface icon-theme' "$repo_root/scripts/install-integration"
grep -Fq 'nautilus.icon-view default-zoom-level small' "$repo_root/scripts/install-integration"

# Dev tooling is pinned: private package, lockfile, Node version, binary pins.
jq -e '.private == true and (.dependencies // {} | length) == 0
  and (.devDependencies | has("eslint") and has("@eslint/js") and has("globals") and has("prettier") and has("markdownlint-cli2"))' \
  "$repo_root/package.json" >/dev/null
test -f "$repo_root/package-lock.json"
[[ "$(<"$repo_root/.nvmrc")" == 26 ]]
grep -Fq 'version="3.14.1"' "$repo_root/tools/install-shfmt"
grep -Fq '76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf' "$repo_root/tools/install-shfmt"
grep -Fq 'version="1.7.12"' "$repo_root/tools/install-actionlint"
grep -Fq '8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8' "$repo_root/tools/install-actionlint"
grep -Fxq 'node_modules/' "$repo_root/.gitignore"
grep -Fxq 'coverage/' "$repo_root/.gitignore"

# CI runs tools/check; release checks before tagging; actions pinned by SHA.
grep -Fq 'tools/check --skip smoke' "$repo_root/.github/workflows/ci.yml"
grep -Fq 'ARANEA_CHECK_REQUIRE_ALL' "$repo_root/.github/workflows/ci.yml"
grep -Fq 'container: archlinux' "$repo_root/.github/workflows/ci.yml"
[[ "$(<"$repo_root/.omarchy-version")" == v4.0.4 ]]
if grep -hE '^\s*-?\s*uses: [^@]+@v[0-9]' "$repo_root"/.github/workflows/*.yml; then
  echo "action pinned by tag, not SHA" >&2
  exit 1
fi
grep -Fq 'persist-credentials: false' "$repo_root/.github/workflows/release-please.yml"
grep -Fq 'tools/check --staged --fast' "$repo_root/.githooks/pre-commit"
grep -Fq 'tools/check --fast' "$repo_root/.githooks/pre-push"
grep -Fq 'package-ecosystem: npm' "$repo_root/.github/dependabot.yml"
# build: and revert: are real commit types here (this branch uses build:).
"$repo_root/tools/check-commit-style.sh" "build: pin a tool"
"$repo_root/tools/check-commit-style.sh" "revert: undo a change"
# The release only tags after tools/check passed on the merged commit.
grep -Fq 'needs: verify' "$repo_root/.github/workflows/release-please.yml"
grep -Fq 'MIT License' "$repo_root/LICENSE"
test -f "$repo_root/SECURITY.md" && test -f "$repo_root/.github/pull_request_template.md"
grep -Fq 'tools/check' "$repo_root/CONTRIBUTING.md"
grep -Fq 'tools/check' "$repo_root/.github/pull_request_template.md"
if grep -Fq 'tests-27%20passing' "$repo_root/README.md"; then
  echo "static test badge" >&2
  exit 1
fi
grep -Fq 'actions/workflow/status/AraneaDev/aranea-desktop/ci.yml' "$repo_root/README.md"
# Hooks do nothing on branches that predate tools/check.
grep -Fq '[ -x tools/check ] || exit 0' "$repo_root/.githooks/pre-commit"
grep -Fq '[ -x tools/check ] || exit 0' "$repo_root/.githooks/pre-push"
echo "toolkit contract passed"
