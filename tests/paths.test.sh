#!/usr/bin/env bash
# Contract for scripts/lib/paths.sh: the XDG base directories fall back to
# their standard defaults, Aranea's state directory honours ARANEA_STATE_ROOT,
# and no script or tool outside the library spells out its own XDG fallback.
# hooks/ are exempt: Omarchy runs the installed hook copies even when the
# theme directory (and so the library) is gone.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
# shellcheck disable=SC1091
source "$repo_root/scripts/lib/paths.sh"

# --- the sandbox sets every XDG variable
[[ "$(xdg_state_home)" == "$XDG_STATE_HOME" ]]
[[ "$(xdg_config_home)" == "$XDG_CONFIG_HOME" ]]
[[ "$(xdg_data_home)" == "$XDG_DATA_HOME" ]]
[[ "$(aranea_state_root)" == "$XDG_STATE_HOME/aranea" ]]
[[ "$(ARANEA_STATE_ROOT=/elsewhere aranea_state_root)" == /elsewhere ]]

# --- unset or empty XDG variables fall back to the standard directories
[[ "$(XDG_STATE_HOME='' xdg_state_home)" == "$HOME/.local/state" ]]
[[ "$(XDG_CONFIG_HOME='' xdg_config_home)" == "$HOME/.config" ]]
[[ "$(XDG_DATA_HOME='' xdg_data_home)" == "$HOME/.local/share" ]]
# shellcheck disable=SC2016 # the inner script expands $1 itself
[[ "$(env -u XDG_STATE_HOME bash -c 'source "$1"; aranea_state_root' _ "$repo_root/scripts/lib/paths.sh")" == "$HOME/.local/state/aranea" ]]

# --- one definition: no other script or tool spells out an XDG fallback
if grep -rnE '\$\{XDG_(STATE|CONFIG|DATA)_HOME:-' "$repo_root/scripts" "$repo_root/tools" "$repo_root/installer" |
  grep -v "^$repo_root/scripts/lib/paths.sh:"; then
  echo "use scripts/lib/paths.sh instead of a local XDG fallback" >&2
  exit 1
fi

echo "paths contract passed"

# Execute the JavaScript path bindings consumed by QML with controlled env.
# Removing the state-root override or using another registry root breaks this.
node - "$repo_root/plugins/araneadev.shared/RuntimePaths.qml" <<'JS'
const fs = require('fs');
const vm = require('vm');
const assert = require('assert');
const source = fs.readFileSync(process.argv[2], 'utf8');
function paths(env) {
  const context = vm.createContext({Quickshell:{env:key => env[key] || ''}});
  for (const name of ['home','xdgStateHome','araneaStateRoot','projectsRegistryPath']) {
    const binding = source.match(new RegExp('readonly property string ' + name + ': ([^\\n]+)'));
    assert.ok(binding, 'missing runtime path ' + name);
    context[name] = vm.runInContext(binding[1], context);
  }
  return context;
}
assert.equal(paths({HOME:'/home/example'}).projectsRegistryPath, '/home/example/.local/state/aranea/projects.json');
assert.equal(paths({HOME:'/home/example',XDG_STATE_HOME:'/xdg',ARANEA_STATE_ROOT:'/custom'}).projectsRegistryPath, '/custom/projects.json');
assert.equal(paths({HOME:'/home/example',XDG_STATE_HOME:'/xdg',ARANEA_STATE_ROOT:''}).projectsRegistryPath, '/xdg/aranea/projects.json');
JS
