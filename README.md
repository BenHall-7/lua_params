# lua_params

lua module capable of opening and saving Smash Ultimate param files via a table structure. Assumes lua version 5.3

## structure

OPEN(filename) returns param file object with a ROOT node

nodes can be one of multiple types:
```lua
TYPES = {
    "bool",
    "sbyte",
    "byte",
    "short",
    "ushort",
    "int",
    "uint",
    "float",
    "hash40",
    "string",
    "list",
    "struct"
}
```
each element is considered a table, and there are 3 categories depending on the type.

structs:

    TYPE    (always equal to "struct")
    HASHES  (an ordered list of the hashes in the struct used to access nodes)
    NODES   (a dictionary of nodes accessed by hash)
    
lists:

    TYPE    (always equal to "list")
    NODES   (an ordered list of nodes; these are assumed to be the same type)

values:

    TYPE    (anything else except "struct" and "list")
    VALUE   (a value depending on the type)

the ROOT of a param file is always a struct

### example

opens fighter_param.prc and divides all aerial landing lag values by 2:
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
