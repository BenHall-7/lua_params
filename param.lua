-- assumes lua version 5.3
local param_util = {
    _VERSION = "1.0",
    _URL = "https://github.com/BenHall-7/lua_params",
    _DESCRIPTION = "Opens or saves Smash Ultimate param files via a table structure"
}

param_util.TYPES = {
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

function param_util.HELP()
    print(param_util._DESCRIPTION)
    print(param_util._URL)
    print("OPEN(filename): returns param file")
    print("SAVE(filename, param): saves param file")
    print("refer to the README for structure")
    print("see example.lua for example usage")
end

function param_util.OPEN(filename)
    local reader = dofile("reader.lua")
    local f = reader.open_read(filename)
    assert(f:read(8) == 'paracobn', "file '"..filename.."' contains invalid header")
    reader.file = f

    -- read header
    local hash_pos, hash_size = 0x10, reader:int()
    local ref_pos, ref_size = hash_pos + hash_size, reader:int()
    local param_pos = ref_pos + ref_size

    -- read hashes
    local hashes = {}
    for i = 1, hash_size / 8 do
        hashes[i] = reader:long()
    end

    -- recursive read
    local read_param, read_struct, read_list, read_value

    read_param = function()
        local type = param_util.TYPES[reader:byte()]

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
    assert(param_util.TYPES[reader.byte()] == "struct", "file does not contain a root element")
    local ROOT = read_struct()

    return ROOT
end

function param_util.SAVE(filename, root_struct)
    local param_writer = dofile("writer.lua")
    local param_f = param_writer.open_write_temp()

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
        if indexof(tbl, value) == nil then
            table.insert(tbl, value)
        end
    end

    local function ref_table_equals(tbl1, tbl2)
        if #tbl1 ~= #tbl2 then
            return false
        else
            for index, sub_tbl1 in ipairs(tbl1) do
                local sub_tbl2 = tbl2[index]
                if sub_tbl1.hash_ ~= sub_tbl2.hash_ or sub_tbl1.offset_ ~= sub_tbl2.offset_ then
                    return false
                end
            end
            return true
        end
    end

    local function get_sorted_copy(tbl)
        local copy = {}
        for i, h in ipairs(tbl) do copy[i] = h end
        table.sort(copy)
        return copy
    end

    local function parse_hashes(param)
        if param.TYPE == "struct" then
            for _, hash in ipairs(param.HASHES) do
                append_no_duplicate(hashes, hash)
                parse_hashes(param.NODES[hash])
            end 
        elseif param.TYPE == "list" then
            for _, p in ipairs(param.NODES) do
                parse_hashes(p)
            end
        elseif param.TYPE == "hash40" then
            append_no_duplicate(hashes, param.VALUE)
        end
    end

    local write_param, write_struct, write_list, write_value

    write_param = function(param)
        local t = param.TYPE
        param_writer.byte(indexof(param_util.TYPES, t))
        if t == "struct" then
            write_struct(param)
        elseif t == "list" then
            write_list(param)
        else
            write_value(param)
        end
    end

    write_struct = function(struct)
        local start = param_f:seek() - 1
        local ref_entry, struct_id = {}, {}
        table.insert(ref_entries, ref_entry)
        param_writer.int(#struct.HASHES)
        
        ref_entry.struct_ = struct_id
        struct_id.pos_ = start + 5
        struct_id.ref_ = ref_entry

        table.insert(unresolved_structs, struct_id)
        param_writer.int(0)
        for index, hash in ipairs(get_sorted_copy(struct.HASHES)) do
            ref_entry[index] = {
                hash_ = indexof(hashes, hash),
                offset_ = param_f:seek() - start
            }
            write_param(struct.NODES[hash])
        end
    end

    write_list = function(list)
        local start, len = param_f:seek() - 1, #list.NODES
        param_writer.int(len)

        local offsets = {}
        param_f:seek("cur", len * 4)
        for index, node in ipairs(list.NODES) do
            offsets[index] = param_f:seek() - start
            write_param(node)
        end

        local last = param_f:seek()
        param_f:seek("set", start + 5)
        for _, n in ipairs(offsets) do
            param_writer.int(n)
        end
        param_f:seek("set", last)
    end

    write_value = function(value)
        local type_ = value.TYPE
        if type_ == "bool" then
            param_writer.bool(value.VALUE)
        elseif type_ == "sbyte" then
            param_writer.sbyte(value.VALUE)
        elseif type_ == "byte" then
            param_writer.byte(value.VALUE)
        elseif type_ == "short" then
            param_writer.short(value.VALUE)
        elseif type_ == "ushort" then
            param_writer.ushort(value.VALUE)
        elseif type_ == "int" then
            param_writer.int(value.VALUE)
        elseif type_ == "uint" then
            param_writer.uint(value.VALUE)
        elseif type_ == "float" then
            param_writer.float(value.VALUE)
        elseif type_ == "hash40" then
            param_writer.int(indexof(hashes, value.VALUE) - 1)
        elseif type_ == "string" then
            local str = value.VALUE
            append_no_duplicate(ref_entries, str)
            local dynamic_ref = {
                pos_ = param_f:seek(),
                str_ = str
            }
            table.insert(unresolved_strings, dynamic_ref)
            param_writer.int(0)
        end
    end

    append_no_duplicate(hashes, 0)
    parse_hashes(root_struct)
    write_param(root_struct)

    -- truncate duplicate ref_entries ; fix the corresponding struct
    local current_index = 1
    while current_index <= #ref_entries do
        local current = ref_entries[current_index]
        if type(current) == "table" then
            for i = current_index - 1, 1, -1 do
                local prev = ref_entries[i]
                if type(prev) == "table" and ref_table_equals(current, prev) then
                    current.struct_.ref_ = prev
                    table.remove(ref_entries, current_index)
                    current_index = current_index - 1
                    break
                end
            end
            current.struct_ = nil
        end
        current_index = current_index + 1
    end

    local header_writer = dofile("writer.lua")
    local header_f = header_writer.open_write(filename)

    header_f:write("paracobn")
    local hash_size, ref_size
    header_writer.long(0)--skip these two for now
    for _, v in ipairs(hashes) do
        header_writer.long(v)
    end
    hash_size = header_f:seek() - 0x10

    local string_offsets = {}
    local ref_start = header_f:seek()
    for i = 1, #ref_entries do
        local entry = ref_entries[i]
        if type(entry) == "table" then
            entry.offset_ = header_f:seek() - ref_start
            for _, pair in ipairs(entry) do
                header_writer.int(pair.hash_ - 1)
                header_writer.int(pair.offset_)
            end
        elseif type(entry) == "string" then
            string_offsets[entry] = header_f:seek() - ref_start
            header_f:write(entry)
            header_writer.byte(0)
        end 
    end
    ref_size = header_f:seek() - ref_start

    for _, struct in ipairs(unresolved_structs) do
        param_f:seek("set", struct.pos_)
        param_writer.int(struct.ref_.offset_)
    end

    for _, i in ipairs(unresolved_strings) do
        param_f:seek("set", i.pos_)
        param_writer.int(string_offsets[i.str_])
    end

    header_f:seek("set", 8)
    header_writer.int(hash_size)
    header_writer.int(ref_size)
    header_f:seek("end", 0)

    param_f:seek("set", 0)
    local param_data = param_f:read("*a")
    header_f:write(param_data)

    header_f:close()
    param_f:close()
end

return param_util