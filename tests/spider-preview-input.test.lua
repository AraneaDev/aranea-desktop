local repo = assert(arg[1], 'repository path required')
local function preview()
    local bindings, callbacks, arm, closed = {}, {}, nil, 0
    package.loaded.mp = nil
    package.preload.mp = function() return {
        commandv=function(cmd) assert(cmd=='quit'); closed=closed+1 end,
        add_forced_key_binding=function(key, name, cb) bindings[key]=cb end,
        observe_property=function(name, kind, cb) callbacks[name]=cb end,
        add_timeout=function(seconds, cb) assert(seconds==1); arm=cb end
    } end
    dofile(repo .. '/branding/3d/preview.lua')
    return {
        mouse=function(pos) callbacks['mouse-pos'](nil, pos) end,
        arm=function() arm() end,
        closed=function() return closed end,
        key=function(key) bindings[key]() end
    }
end

-- Pointer entry can arrive after the launch grace with no actual movement.
local delayed = preview()
delayed.mouse({hover=false,x=0,y=0})
delayed.arm()
delayed.mouse({hover=true,x=1920,y=608})
assert(delayed.closed()==0, 'delayed first pointer entry must establish a baseline')
delayed.mouse({hover=true,x=1921,y=608})
assert(delayed.closed()==0, 'small entry jitter must not dismiss')
delayed.mouse({hover=true,x=1940,y=608})
assert(delayed.closed()==1, 'real movement after delayed entry must dismiss')

-- Leaving the window invalidates its origin; re-entry gets a fresh baseline.
local reentry = preview()
reentry.mouse({hover=true,x=100,y=100})
reentry.arm()
reentry.mouse({hover=false,x=0,y=0})
assert(reentry.closed()==0, 'pointer leaving must not dismiss')
reentry.mouse({hover=true,x=1800,y=600})
assert(reentry.closed()==0, 'pointer re-entry must establish a new baseline')
reentry.mouse({hover=true,x=1808,y=610})
assert(reentry.closed()==0, 'the existing 18-pixel jitter boundary must remain')
reentry.mouse({hover=true,x=1809,y=610})
assert(reentry.closed()==1, 'movement beyond the baseline threshold must dismiss')

-- Missing pointer/hover observations are outside, not reusable coordinates.
local unknown = preview()
unknown.mouse({hover=true,x=100,y=100})
unknown.arm()
unknown.mouse(nil)
unknown.mouse({hover=true,x=900,y=600})
assert(unknown.closed()==0, 'missing pointer state must clear the old baseline')
unknown.mouse({x=0,y=0})
unknown.mouse({hover=true,x=1800,y=600})
assert(unknown.closed()==0, 'unknown hover state must clear the old baseline')

-- Real in-window motion still observes the original startup grace and threshold.
local startup = preview()
startup.mouse({hover=true,x=100,y=100})
startup.mouse({hover=true,x=500,y=500})
assert(startup.closed()==0, 'launch-time pointer warp must not dismiss')
startup.arm()
startup.mouse({hover=true,x=501,y=500})
assert(startup.closed()==0, 'small movement after launch must not dismiss')
startup.mouse({hover=true,x=530,y=500})
assert(startup.closed()==1, 'real movement after launch must dismiss')

local keys = preview()
for count, key in ipairs({'ANY_UNICODE','ESC','MBTN_LEFT','MBTN_RIGHT','WHEEL_UP','F12'}) do
    keys.key(key)
    assert(keys.closed()==count, key .. ' must still dismiss')
end
print('Preview input: delayed entry and re-entry reset origin; real motion, keys and clicks dismiss')
