#!/usr/bin/env bash
# Shared inert preview process policy; sourced by the offscreen renderers.

# Install fixed command traps in the isolated capture work directory.
render_capture_install_traps() {
  local work="$1" program
  mkdir -p "$work/traps"
  for program in claude codex notify-send aranea-agent-store aranea-agent-hook aranea-agent-hook-worker aranea-agent-heartbeat aranea-agent-adapter aranea-agent-identity aranea-agent-launch aranea-project-launch aranea-project-identity omarchy-shell aranea aranea-project-store aranea-project-discover aranea-project-tools code nvim alacritty kitty foot ghostty hyprctl; do
    cat >"$work/traps/$program" <<'CAPTURE_TRAP'
#!/usr/bin/env bash
# Shared Style geometry probes receive fixed offscreen values, never live IPC.
if [[ "${0##*/}" == hyprctl && "$*" == '-j getoption general:gaps_out' || "${0##*/}" == hyprctl && "$*" == '-j getoption decoration:rounding' ]]; then
  printf '{"int":0}\n'
  exit 0
fi
printf '%s %s\n' "${0##*/}" "$*" >>"$ARANEA_CAPTURE_EXECUTION_LOG"
exit 99
CAPTURE_TRAP
    chmod +x "$work/traps/$program"
  done
}
