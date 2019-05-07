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

function GET_SORTED_COPY(tbl)
    local copy = {}
    for i, h in ipairs(tbl) do copy[i] = h end
    table.sort(copy)
    return copy
end

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

    read_value = function(type_)
        assert(type(type_) == "string", "this shouldn't fail")
        local param = {TYPE = type_}
        if type_ == "bool" then
            param.VALUE = reader.bool()
        elseif type_ == "sbyte" then
            param.VALUE = reader.sbyte()
        elseif type_ == "byte" then
            param.VALUE = reader.byte()
        elseif type_ == "short" then
            param.VALUE = reader.short()
        elseif type_ == "ushort" then
            param.VALUE = reader.ushort()
        elseif type_ == "int" then
            param.VALUE = reader.int()
        elseif type_ == "uint" then
            param.VALUE = reader.uint()
        elseif type_ == "float" then
            param.VALUE = reader.float()
        elseif type_ == "hash40" then
            param.VALUE = hashes[reader.int() + 1]
        elseif type_ == "string" then
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
    local unresolved_structs = {}
    local unresolved_strings = {}

    local function indexof(tbl, value)
        for i, v in ipairs(tbl) do
            if v == value then return i end
        end
    end

    local function append_no_duplicate(tbl, value)
        local i
        for i = 1, #tbl do
            if tbl[i] == value then return end
        end
        -- +1?
        tbl[i] = value
    end

    local function parse_hashes(param)
        if param.TYPE == "struct" then
            for hash, node in ipairs(param.HASHES) do
                append_no_duplicate(hashes, hash)
                parse_hashes(node)
            end 
        elseif param.TYPE == "list" then
            for _, p in ipairs(param) do
                parse_hashes(p)
            end
        elseif param.TYPE == "hash40" then
            append_no_duplicate(hashes, param.VALUE)
        end
    end

    local write_param, write_struct, write_list, write_value

    write_param = function(param)
        local t = param.TYPE
        writer.byte(indexof(TYPES, t))
        if t == "struct" then
            write_struct(param)
        elseif t == "list" then
            write_list(param)
        else
            write_value(param)
        end
    end

    write_struct = function(struct)
        local start = f:seek() - 1
        local ref_entry = {cor_struct = struct}
        table.insert(ref_entries, ref_entry)
        writer.int(#struct.NODES)
        -- after all structs are generated (with param offsets/etc)
        -- we filter down ref_entries and fix each struct's reference to it
        local dynamic_ref = {
            pos_ = start + 5,
            ref_ = ref_entry
        }
        table.insert(unresolved_structs, dynamic_ref)
        writer.int(0)
        for index, hash in ipairs(GET_SORTED_COPY(struct.HASHES)) do
            ref_entry[index] = {
                hash_ = indexof(hashes, hash),
                offset_ = f:seek() - start
            }
            write_param(struct.NODES[hash])
        end
    end

    write_list = function(list)
        local start, len = f:seek() - 1, #list.NODES
        writer.int(len)

        local offsets = {}
        f:seek("cur", len * 4)
        for index, node in ipairs(list.NODES) do
            offsets[index] = f:seek() - start
            write_param(node)
        end

        local last = f:seek()
        f:seek("set", start + 5)
        for _, n in ipairs(offsets) do
            writer.int(n)
        end
        f:seek("set", last)
    end

    write_value = function(value)
        local type_ = value.TYPE
        if type_ == "bool" then
            writer.bool(value.VALUE)
        elseif type_ == "sbyte" then
            writer.sbyte(value.VALUE)
        elseif type_ == "byte" then
            writer.byte(value.VALUE)
        elseif type_ == "short" then
            writer.short(value.VALUE)
        elseif type_ == "ushort" then
            writer.ushort(value.VALUE)
        elseif type_ == "int" then
            writer.int(value.VALUE)
        elseif type_ == "uint" then
            writer.uint(value.VALUE)
        elseif type_ == "float" then
            writer.float(value.VALUE)
        elseif type_ == "hash40" then
            writer.int(indexof(value.VALUE) - 1)
        elseif type_ == "string" then
            local str = value.VALUE
            append_no_duplicate(ref_entries, str)
            local dynamic_ref = {
                pos_ = f:seek(),
                str_ = str
            }
            table.insert(unresolved_strings, dynamic_ref)
            writer.int(0)
        end
    end

    append_no_duplicate(hashes, 0)
    parse_hashes(PARAM_FILE.ROOT)
    write_param(PARAM_FILE.ROOT)

    local i = 1
    while i <= #ref_entries do
        print("stub")
    end

    --f:write("paracobn")
    --writer.int()
end