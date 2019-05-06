-- assumes lua version 5.3

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

function HELP()
    print("args:")
    print("to open:", "'o [file name]'")
    print("to save:", "'s [file name] [param object]")
    return
end

if (#arg < 2) then
    HELP()
end

local mode, filename = arg[1], arg[2]
assert(mode == "o" or mode == "s", "invalid arg [#1]: mode")
if mode == "o" then
    local reader = require("reader")
    local f = reader.open_read(filename)
    assert(f:read(8) == 'paracobn', "file '"..filename.."' contains invalid header")
    reader.file = f

    local PARAM_FILE = {}

    -- Read header
    local hash_pos, hash_size = 0x10, reader:int()
    local ref_pos, ref_size = hash_pos + hash_size, reader:int()
    local param_pos = ref_pos + ref_size

    -- Read hashes
    local hashes = {}
    for i = 1, hash_size / 8 do
        hashes[i] = reader:long()
    end

    -- recursive read
    local read_param, read_struct, read_list, read_value

    read_param = function()
        local type = TYPES[reader:byte()]

        if (type == "struct") then
            return read_struct()
        elseif (type == "list") then
            return read_list()
        else
            return read_value(type)
        end
    end

    read_struct = function()
        local struct = {TYPE = "struct"}
        local start, size, ref_offset =  f:seek() - 1, reader.int(), reader.int()
        f:seek("set", ref_pos + ref_offset)

        -- "indices" = array of hash indices so that we can sort/iterate with it
        -- "nodes" = dictionary of hash/offsets
        local indices, nodes = {}, {}
        for i = 1, size do
            local hash_index = reader.int() + 1
            local node_offset = reader.int()
            
            indices[i] = hash_index
            nodes[hashes[hash_index]] = node_offset
        end
        table.sort(indices)
        -- we replace each hash index with the true hash
        for a, b in ipairs(indices) do
            indices[a] = hashes[b]
        end
        -- similarly, we replace each offset with a node
        for hash, offset in pairs(nodes) do
            f:seek("set", start + offset)
            nodes[hash] = read_param()
        end

        struct.NODES = nodes
        struct.HASHES = indices
        return struct
    end

    read_list = function()
        local list = {TYPE = "list"}
        local start, size =  f:seek() - 1, reader.int()
        local offsets = {}
        for i = 1, size do
            offsets[i] = reader.int()
        end

        local nodes = {}
        for i = 1, size do
            f:seek("set", start + offsets[i])
            nodes[i] = read_param()
        end

        list.NODES = nodes
        return list
    end

    read_value = function(_type)
        assert(type(_type) == "string", "this shouldn't fail")
        local param = {TYPE = _type}
        if _type == "bool" then
            param.VALUE = reader.bool()
        elseif _type == "sbyte" then
            param.VALUE = reader.sbyte()
        elseif _type == "byte" then
            param.VALUE = reader.byte()
        elseif _type == "short" then
            param.VALUE = reader.short()
        elseif _type == "ushort" then
            param.VALUE = reader.ushort()
        elseif _type == "int" then
            param.VALUE = reader.int()
        elseif _type == "uint" then
            param.VALUE = reader.uint()
        elseif _type == "float" then
            param.VALUE = reader.float()
        elseif _type == "hash40" then
            param.VALUE = hashes[reader.int() + 1]
        elseif _type == "string" then
            param.VALUE = reader.string(ref_pos)
        end

        return param
    end

    -- Read param data
    f:seek("set", param_pos)
    assert(TYPES[reader.byte()] == "struct", "file does not contain a root element")
    PARAM_FILE.ROOT = read_struct()

    return PARAM_FILE
else
    if #arg < 3 then
        HELP()
    end

    local writer = require("writer")
    local f = writer.open_write("param_data.temp")

    local PARAM_FILE = arg[3]
    local hashes = {}
    local ref_entries = {}

    local function indexof(tbl, value)
        for i, v in ipairs(tbl) do
            if v == value then return i end
        end
    end

    local function append_with_check(tbl, value)
        local i
        for i = 1, #tbl do
            if tbl[i] == value then return end
        end
        tbl[i] = value
    end

    local function get_sorted_indices(struct)
        local copy = {}
        for i, h in ipairs(struct.HASHES) do copy[i] = h end
        table.sort(copy)
        return copy
    end

    local function parse_hashes(param)
        if param.TYPE == "struct" then
            for hash, node in ipairs(param.HASHES) do
                append_with_check(hashes, hash)
                parse_hashes(node)
            end 
        elseif param.TYPE == "list" then
            for _, p in ipairs(param) do
                parse_hashes(p)
            end
        elseif param.TYPE == "hash40" then
            append_with_check(hashes, param.VALUE)
        end
    end

    local write_param, write_struct, write_list, write_value

    write_struct = function(struct)
        for _, hash in ipairs(get_sorted_indices(struct)) do
            local node = struct.NODES[hash]
        end
    end

    append_with_check(hashes, 0)
    parse_hashes(PARAM_FILE.ROOT)
    --f:write("paracobn")
    --writer.int()
end