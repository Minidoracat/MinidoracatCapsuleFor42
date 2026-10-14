-- Pack & Throw: JSON that keeps Lua key types.
-- Every table is a JSON object. Keys: string "abc" stays "abc"; a string starting with "#" gets one more "#";
-- a number key n is written "#<n>". Values: string, finite number, boolean, table. Anything else fails with a path.
-- Pure Lua (Kahlua and standard Lua). Kahlua has no next/xpcall and no table.sort here.
require "MinidoracatPackThrow/Core"
local M = MinidoracatPackThrow
local Json = {}
M.Json = Json

local MAX_DEPTH = 64
local HUGE = math.huge
-- Kahlua strings are UTF-16 and string.char takes any code unit; standard Lua needs UTF-8 bytes.
local WIDE_CHAR = pcall(string.char, 256)

-- Kahlua tostring(number) is Java Double.toString (round-trips); standard Lua 5.4 uses %.14g, so fall back.
local function numStr(n)
    local s = tostring(n)
    if tonumber(s) ~= n then s = string.format("%.17g", n) end
    return s
end
local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
local HEX = "0123456789abcdef"
-- Only control characters reach the \u path (< 0x20, 0x7f; Kahlua may also class 0x80-0x9f as %c).
local function escChar(c)
    local e = ESC[c]
    if e then return e end
    local b = string.byte(c)
    local hi, lo = math.floor(b / 16) + 1, b % 16 + 1
    return "\\u00" .. string.sub(HEX, hi, hi) .. string.sub(HEX, lo, lo)
end
local function str(s)
    return '"' .. string.gsub(s, '[%c"\\]', escChar) .. '"'
end

local function joinPath(path, k)
    if path == "" then return tostring(k) end
    return path .. "." .. tostring(k)
end

local function encodeValue(v, path, depth, out)
    local t = type(v)
    if t == "string" then
        out[#out + 1] = str(v)
    elseif t == "number" then
        if v ~= v or v == HUGE or v == -HUGE then return path end
        out[#out + 1] = numStr(v)
    elseif t == "boolean" then
        out[#out + 1] = v and "true" or "false"
    elseif t == "table" then
        if depth >= MAX_DEPTH then return path end
        out[#out + 1] = "{"
        local first = true
        for k, sub in pairs(v) do
            local kt, key = type(k), nil
            if kt == "string" then
                key = string.sub(k, 1, 1) == "#" and "#" .. k or k
            elseif kt == "number" and k == k and k ~= HUGE and k ~= -HUGE then
                key = "#" .. numStr(k)
            else
                return joinPath(path, "<" .. kt .. " key>")
            end
            if not first then out[#out + 1] = "," end
            first = false
            out[#out + 1] = str(key)
            out[#out + 1] = ":"
            local bad = encodeValue(sub, joinPath(path, k), depth + 1, out)
            if bad then return bad end
        end
        out[#out + 1] = "}"
    else
        return path == "" and "<" .. t .. ">" or path
    end
    return nil
end

-- Returns the JSON text, or nil plus the path of the first value that cannot be stored.
function Json.encode(v)
    local out = {}
    local bad = encodeValue(v, "", 0, out)
    if bad then return nil, bad end
    return table.concat(out)
end

-- ---------------------------------------------------------------- decode
local function toUtf8(code)
    if code < 0x80 then return string.char(code) end
    if code < 0x800 then
        return string.char(0xC0 + math.floor(code / 0x40), 0x80 + code % 0x40)
    end
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + math.floor(code / 0x40) % 0x40, 0x80 + code % 0x40)
end

local UNESC = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

-- Errors carry a "json: " marker; Json.decode turns them into a nil, message return.
local function fail(i, what)
    error("json: " .. what .. " at " .. tostring(i))
end

local function skip(s, i)
    return string.find(s, "[^ \t\r\n]", i) or #s + 1
end

local function parseString(s, i)
    -- s[i] is the opening quote
    local parts, pos = {}, i + 1
    while true do
        local j = string.find(s, '["\\]', pos)
        if not j then fail(i, "unterminated string") end
        parts[#parts + 1] = string.sub(s, pos, j - 1)
        if string.sub(s, j, j) == '"' then return table.concat(parts), j + 1 end
        local e = string.sub(s, j + 1, j + 1)
        if e == "u" then
            local hex = string.sub(s, j + 2, j + 5)
            local code = string.find(hex, "^%x%x%x%x$") and tonumber(hex, 16)
            if not code then fail(j, "bad \\u escape") end
            parts[#parts + 1] = (code < 0x80 or WIDE_CHAR) and string.char(code) or toUtf8(code)
            pos = j + 6
        else
            local c = UNESC[e]
            if not c then fail(j, "bad escape") end
            parts[#parts + 1] = c
            pos = j + 2
        end
    end
end

local parseValue

local function decodeKey(k, at)
    if string.sub(k, 1, 2) == "##" then return string.sub(k, 2) end
    if string.sub(k, 1, 1) == "#" then
        local n = tonumber(string.sub(k, 2))
        if not n then fail(at, "bad number key") end
        return n
    end
    return k
end

local function parseObject(s, i, depth)
    if depth >= MAX_DEPTH then fail(i, "too deep") end
    local t = {}
    i = skip(s, i + 1)
    if string.sub(s, i, i) == "}" then return t, i + 1 end
    while true do
        if string.sub(s, i, i) ~= '"' then fail(i, "expected key") end
        local k
        k, i = parseString(s, i)
        local key = decodeKey(k, i)
        i = skip(s, i)
        if string.sub(s, i, i) ~= ":" then fail(i, "expected :") end
        local v
        v, i = parseValue(s, skip(s, i + 1), depth + 1)
        t[key] = v
        i = skip(s, i)
        local c = string.sub(s, i, i)
        if c == "}" then return t, i + 1 end
        if c ~= "," then fail(i, "expected , or }") end
        i = skip(s, i + 1)
    end
end

parseValue = function(s, i, depth)
    local c = string.sub(s, i, i)
    if c == "{" then return parseObject(s, i, depth) end
    if c == '"' then return parseString(s, i) end
    if string.sub(s, i, i + 3) == "true" then return true, i + 4 end
    if string.sub(s, i, i + 4) == "false" then return false, i + 5 end
    local a, b = string.find(s, "^-?%d+%.?%d*[eE]?[-+]?%d*", i)
    if a then
        local n = tonumber(string.sub(s, a, b))
        if n then return n, b + 1 end
    end
    fail(i, "unexpected value")
end

-- Returns the value, or nil plus an error message. Trailing garbage is an error.
function Json.decode(s)
    if type(s) ~= "string" then return nil, "not a string" end
    local ok, v, i = pcall(parseValue, s, skip(s, 1), 0)
    if not ok then return nil, tostring(v) end
    if skip(s, i) <= #s then return nil, "trailing data at " .. i end
    return v
end

-- Deep copy of plain data (tables copied, other values shared). Used to detach modData from the live object.
function Json.copy(v, depth)
    if type(v) ~= "table" then return v end
    depth = depth or 0
    if depth >= MAX_DEPTH then return v end
    local t = {}
    for k, sub in pairs(v) do t[k] = Json.copy(sub, depth + 1) end
    return t
end

-- Copy of v keeping only what the engine itself persists (KahluaTableImpl.save: keys string/number, values
-- string/number/boolean/table; anything else is silently dropped on save and on the network).
-- Dropped entries are appended to `skipped` as paths. Json.encode never fails on the result.
-- ponytail: NaN/+-inf numbers are dropped too (the engine keeps them, JSON cannot); they are vanishingly rare in modData.
local function storableNumber(n)
    return n == n and n ~= HUGE and n ~= -HUGE
end
function Json.storable(v, path, skipped, depth)
    depth = depth or 0
    local t = type(v)
    if t == "string" or t == "boolean" then return v end
    if t == "number" then
        if storableNumber(v) then return v end
    elseif t == "table" and depth < MAX_DEPTH then
        local out = {}
        for k, sub in pairs(v) do
            local kt = type(k)
            if kt == "string" or (kt == "number" and storableNumber(k)) then
                local c = Json.storable(sub, joinPath(path, k), skipped, depth + 1)
                if c ~= nil then out[k] = c end
            else
                skipped[#skipped + 1] = joinPath(path, "<" .. kt .. " key>")
            end
        end
        return out
    end
    skipped[#skipped + 1] = path
    return nil
end

return Json
