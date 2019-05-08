local writer = {}

-- for reference: https://www.lua.org/manual/5.3/manual.html#6.4.2

function writer.open_write(filename)
    writer.file = io.open(filename, "wb")
    return writer.file
end

function writer.open_write_temp()
    writer.file = io.tmpfile()
    return writer.file
end

function writer.bool(n)
    if n == true then
        writer.byte(1)
    else
        writer.byte(0)
    end
end

function writer.sbyte(n)
    writer.file:write(string.pack('b', n))
end

function writer.byte(n)
    return writer.file:write(string.pack('B', n))
end

function writer.short(n)
    return writer.file:write(string.pack('i2', n))
end

function writer.ushort(n)
    return writer.file:write(string.pack('I2', n))
end

function writer.int(n)
    return writer.file:write(string.pack('i4', n))
end

function writer.uint(n)
    return writer.file:write(string.pack('I4', n))
end

function writer.float(n)
    return writer.file:write(string.pack('f', n))
end

function writer.long(n)
    return writer.file:write(string.pack('i8', n))
end

return writer