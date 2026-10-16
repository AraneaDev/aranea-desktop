# Default profile drafts from the installed tool probe; mirrors ProjectProfiles.js presets().
# Input: none (-n). Argument: $tools, the aranea-project-tools --json observation.
# Only IDs the registry schema accepts (projects-registry.jq editor/terminal/agent) may become drafts.
def known($group): if $group == "editors" then ["code","nvim"] elif $group == "terminals" then ["alacritty","kitty","foot","ghostty"] else ["claude","codex"] end;
def choices($group): known($group) as $ids | ($tools[$group] // []) | if type == "array" then . else [] end
  | map(select(type == "object" and .available == true and .supported == true and (.id | type == "string") and (.id as $id | $ids | index($id) != null)));
def preferred($group; $key):
  (choices($group)) as $options
  | (($tools.defaults // {})[$key]) as $id
  | if any($options[]; .id == $id) then $id elif ($options|length) > 0 then $options[0].id else null end;
def has_editor($id): any(choices("editors")[]; .id == $id);
preferred("terminals"; "terminalId") as $terminal
| preferred("agents"; "agentId") as $agent
| [ (if has_editor("code") then {name:"VS Code",roles:["editor"],tools:{editorId:"code",terminalId:null,agentId:null}} else empty end),
    (if $terminal and $agent then {name:"Terminal + Agent",roles:["terminal","agent"],tools:{editorId:null,terminalId:$terminal,agentId:$agent}} else empty end),
    (if $terminal and has_editor("nvim") then {name:"Neovim",roles:["editor"],tools:{editorId:"nvim",terminalId:$terminal,agentId:null}} else empty end),
    (if $terminal then {name:"Terminal",roles:["terminal"],tools:{editorId:null,terminalId:$terminal,agentId:null}} else empty end) ]
