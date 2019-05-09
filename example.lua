--opens fighter_param.prc and ParamLabels.csv
--divides all landing lag values by 2
PARAM_UTIL = require("param")
H40 = require("hash40")
local param = PARAM_UTIL.OPEN("fighter_param.prc")
local s2h = H40.LOAD_STRING_HASH_TBL("ParamLabels.csv")

local list = param.ROOT.NODES[s2h["fighter_param_table"]]
for _, struct in ipairs(list.NODES) do
    local nodes = struct.NODES
    local names = {
        "landing_attack_air_frame_n",
        "landing_attack_air_frame_f",
        "landing_attack_air_frame_b",
        "landing_attack_air_frame_hi",
        "landing_attack_air_frame_lw",
    }
    for __, name in ipairs(names) do
        local hash = s2h[name]
        local param = nodes[hash]
        param.VALUE = math.floor(param.VALUE / 2)
    end
end
PARAM_UTIL.SAVE("fighter_param_new.prc", param)