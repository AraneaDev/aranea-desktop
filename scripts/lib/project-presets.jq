# Default profile drafts from the installed tool probe; mirrors ProjectProfiles.js presets().
# Input: none (-n). Argument: $tools, the aranea-project-tools --json observation.
def choices($group): ($tools[$group] // []) | map(select(.available == true and .supported == true));
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
