local reader = {}

-- for reference: https://www.lua.org/manual/5.3/manual.html#6.4.2

function reader.open_read(filename)
    reader.file = assert(io.open(filename, "rb"))
    return reader.file
end

function reader.bool()
    local v = reader.byte()
    if v == 0 then
        return false
    end
    return true
end

function reader.sbyte()
    return string.unpack('b', reader.file:read(1))
end

function reader.byte()
    return string.unpack('B', reader.file:read(1))
end

function reader.short()
    return string.unpack('i2', reader.file:read(2))
end

function reader.ushort()
    return string.unpack('I2', reader.file:read(2))
end

function reader.int()
    return string.unpack('i4', reader.file:read(4))
end

function reader.uint()
    return string.unpack('I4', reader.file:read(4))
end

function reader.float()
    return string.unpack('f', reader.file:read(4))
end

function reader.long()
    return string.unpack('i8', reader.file:read(8))
end

function reader.string(base_offset)
    local prev = reader.file:seek()
    reader.file:seek("set", base_offset + reader.int())

    local string = ""
    while true do
        local char = reader.file:read(1)
        if char == '\0' then break end
        string = string..char
    end

    reader.file:seek("set", prev)
    return string
end

return reader