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
end

if (#arg < 2) then
    HELP()
    return
end

local mode, filename = arg[1], arg[2]
if mode ~= "o" and mode ~= "s" then
    print("invalid arg [#1]: mode")
    HELP()
    return
end

if mode == "o" then
    local reader = dofile("reader.lua")
    local f = reader.open_read(filename)
    assert(f:read(8) == 'paracobn', "file '"..filename.."' contains invalid header")
    reader.file = f

    local PARAM_FILE = {}

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
        return
    end

    local writer = dofile("writer.lua")
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
        local ref_entry, struct_id = {}, {}
        table.insert(ref_entries, ref_entry)
        writer.int(#struct.HASHES)
        
        ref_entry.struct_ = struct_id
        struct_id.pos_ = start + 5
        struct_id.ref_ = ref_entry

        table.insert(unresolved_structs, struct_id)
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
            writer.int(indexof(hashes, value.VALUE) - 1)
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

    -- truncate duplicate ref_entries ; fix the corresponding struct
    local current_index = 1
    while current_index < #ref_entries do
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

    local main_writer = dofile("writer.lua")
    local main_f = main_writer.open_write(filename)

    main_f:write("paracobn")
    local hash_size, ref_size
    main_writer.long(0)--skip these two for now
    for _, v in ipairs(hashes) do
        main_writer.long(v)
    end
    hash_size = main_f:seek() - 0x10

    local string_offsets = {}
    local ref_start = main_f:seek()
    for i = 1, #ref_entries do
        local entry = ref_entries[i]
        if type(entry) == "table" then
            entry.offset_ = main_f:seek() - ref_start
            for _, pair in ipairs(entry) do
                main_writer.int(pair.hash_ - 1)
                main_writer.int(pair.offset_)
            end
        elseif type(entry) == "string" then
            string_offsets[entry] = main_f:seek() - ref_start
            main_f:write(entry)
            main_writer.byte(0)
        end 
    end
    ref_size = f:seek() - ref_start

    for _, struct in ipairs(unresolved_structs) do
        f:seek("set", struct.pos_)
        writer.int(struct.ref_.offset_)
    end

    for _, i in ipairs(unresolved_strings) do
        f:seek("set", i.pos_)
        writer.int(string_offsets[i.str_])
    end

    main_f:seek("set", 8)
    main_writer.int(hash_size)
    main_writer.int(ref_size)

    main_f:close()
    f:close()
end