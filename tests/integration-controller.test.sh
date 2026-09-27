#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$repo_root/tests/lib/sandbox.sh"
state="$HOME/.local/state/aranea/integrations"
ctl="$repo_root/scripts/aranea-integrations"
status="$("$ctl" status --json)"
grep -Fq '"id":"session","status":"inactive","availability":"available"' <<<"$status"
"$ctl" activate session --yes >/dev/null
test -L "$XDG_CONFIG_HOME/omarchy/session/aranea.css"
[[ "$(<"$state/session")" == active ]]
grep -Fqx "$XDG_CONFIG_HOME/omarchy/session/aranea.css" "$state/session.files"
# Deactivate restores, forgets and marks inactive — even though the target
# was already linked before activate ran (the hooks link everything).
"$ctl" deactivate session >/dev/null
test ! -e "$XDG_CONFIG_HOME/omarchy/session/aranea.css"
[[ "$(<"$state/session")" == inactive ]]
if grep -Fqx "$XDG_CONFIG_HOME/omarchy/session/aranea.css" "$HOME/.local/state/aranea/managed-files"; then echo "deactivate left the target in the ledger" >&2; exit 1; fi
"$repo_root/scripts/install-integration" session --yes >/dev/null
"$ctl" activate session --yes >/dev/null
grep -Fqx "$XDG_CONFIG_HOME/omarchy/session/aranea.css" "$state/session.files"
if "$ctl" activate nope --yes >/dev/null 2>&1; then exit 1; fi
echo "integration controller contract passed"
