local bindings, callbacks, armed, closed = {}, {}, nil, 0
package.preload.mp = function() return {
 commandv=function(cmd) assert(cmd=='quit'); closed=closed+1 end,
 add_forced_key_binding=function(key, name, cb) bindings[key]=cb end,
 observe_property=function(name, kind, cb) callbacks[name]=cb end,
 add_timeout=function(seconds, cb) assert(seconds==1); armed=cb end
} end
dofile(assert(arg[1], 'repository path required') .. '/branding/3d/preview.lua')
local mouse=callbacks['mouse-pos']
mouse(nil,{x=100,y=100}); mouse(nil,{x=500,y=500}); assert(closed==0)
armed(); mouse(nil,{x=501,y=500}); assert(closed==0)
mouse(nil,{x=530,y=500}); assert(closed==1)
for _,k in ipairs({'ANY_UNICODE','ESC','MBTN_LEFT','F12'}) do bindings[k]() end
assert(closed==5)
print('Preview input: startup warp ignored; mouse motion, keys and clicks dismiss')
