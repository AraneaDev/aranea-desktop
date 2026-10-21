-- Input belongs to this mpv instance only; no idle, lock or compositor changes.
local mp = require('mp')
local armed = false
local origin = nil
local function close()
    mp.commandv('quit')
end
local keys = {'ANY_UNICODE', 'ESC', 'SPACE', 'ENTER', 'TAB', 'BS', 'DEL',
    'INS', 'HOME', 'END', 'PGUP', 'PGDWN', 'UP', 'DOWN', 'LEFT', 'RIGHT',
    'MBTN_LEFT', 'MBTN_RIGHT', 'MBTN_MID', 'WHEEL_UP', 'WHEEL_DOWN'}
for i = 1, 12 do
    keys[#keys + 1] = 'F' .. i
end
for i, key in ipairs(keys) do
    mp.add_forced_key_binding(key, 'aranea-dismiss-' .. i, close)
end
mp.observe_property('mouse-pos', 'native', function(_, pos)
    if not pos or not pos.x or not pos.y then return end
    if not armed or not origin then
        origin = {x = pos.x, y = pos.y}
        return
    end
    -- Ignore launch-time pointer warps and tiny sensor jitter.
    if math.abs(pos.x - origin.x) + math.abs(pos.y - origin.y) > 18 then close() end
end)
mp.add_timeout(1, function() armed = true end)
