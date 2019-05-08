# lua_params

lua module capable of opening and saving Smash Ultimate param files via a table structure. Assumes lua version 5.3

example: opens fighter_param.prc and divides all aerial landing lag values by 2:
```lua
PARAM_UTIL = require("param")
local param = PARAM_UTIL.OPEN("fighter_param.prc")
local list = param.ROOT.NODES[0x131f0d7ade] -- fighter_param_table
--[[
0x1a4262b54f,landing_attack_air_frame_b
0x1a450f7156,landing_attack_air_frame_f
0x1bfaa2e04f,landing_attack_air_frame_hi
0x1b64c11828,landing_attack_air_frame_lw
0x1a4bd4f964,landing_attack_air_frame_n
]]
for _, struct in ipairs(list.NODES) do
    local nodes = struct.NODES
    for __, hash in ipairs({0x1a4bd4f964,0x1a450f7156,0x1a4262b54f,0x1bfaa2e04f,0x1b64c11828}) do
        local param = nodes[hash]
        param.VALUE = math.floor(param.VALUE / 2)
    end
end
PARAM_UTIL.SAVE("fighter_param_new.prc", param)
```
