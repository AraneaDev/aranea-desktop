# Supported tool IDs per group: the one list the registry schema and default presets share.
# Must name exactly what scripts/aranea-project-tools probes (tests/projects-profile-seed.test.sh checks).
def tool_ids: {editors: ["code", "nvim"], terminals: ["alacritty", "kitty", "foot", "ghostty"], agents: ["claude", "codex"]};
# Whether the input is one of the group's supported IDs; only exact strings match.
def tool_id($group): . as $id | any(tool_ids[$group][]; . == $id);
