-- Vehicle Capsule: admin index over the snapshot files, Zomboid/Lua/MinidoracatVehicleCapsule/index.json.
-- One row per capsule (state, vehicle, players, times, recorded spot); the admin panel pages through it 50 rows at a
-- time so a server with thousands of records never sends more than one page (sendServerCommand caps a packet at ~1 MB).
-- The rows follow every Store read and write (Store.listeners), so a row the index missed (crash between the snapshot
-- write and the next flush) heals the first time its file is read; on load, files the index does not know are read in.
-- The index is derived data: a missing or broken file is rebuilt from packs/.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Json"
require "MinidoracatVehicleCapsule/Store"
local M = MinidoracatVehicleCapsule
local Json, Store = M.Json, M.Store
local Index = {}
M.Index = Index

Index.FILE = "MinidoracatVehicleCapsule/index.json"
Index.PAGE_SIZE = 50
Index.FLUSH_MS = 1000
Index.STATES = { "PACKED", "UNPACKED", "RESTORED", "VOID" }

local rows       -- capsuleId -> row; nil until loaded
local order      -- capsule ids, newest pack first; nil when it has to be rebuilt
local dirty, lastFlush = false, nil

-- Stable iterative merge sort (the family gate bans the recursive built-in sort: Kahlua depth limits on big inputs).
local function msort(a, less)
    local n = #a
    if n < 2 then return a end
    local src, dst, width = a, {}, 1
    while width < n do
        local i = 1
        while i <= n do
            local mid, hi = math.min(i + width, n + 1), math.min(i + 2 * width, n + 1)
            local l, r, k = i, mid, i
            while l < mid and r < hi do
                if less(src[r], src[l]) then dst[k] = src[r]; r = r + 1 else dst[k] = src[l]; l = l + 1 end
                k = k + 1
            end
            while l < mid do dst[k] = src[l]; l = l + 1; k = k + 1 end
            while r < hi do dst[k] = src[r]; r = r + 1; k = k + 1 end
            i = i + 2 * width
        end
        src, dst = dst, src
        width = width * 2
    end
    return src
end
Index.sort = msort

-- The last history entry that names a car (same rule as Admin.recordedCar; Admin requires Unpack, the index must not).
local function recorded(h)
    for i = #h, 1, -1 do
        if h[i].car ~= nil then return h[i] end
    end
    return {}
end

-- Plain row from a snapshot. `who` is every player name in the history, lower case, comma separated, for search.
function Index.row(capsuleId, snap)
    local h = type(snap.history) == "table" and snap.history or {}
    local first, last, e = h[1] or {}, h[#h] or {}, recorded(h)
    local names, seen = {}, {}
    local function add(n)
        n = type(n) == "string" and string.lower(n) or nil
        if n and n ~= "" and n ~= "-" and not seen[n] then seen[n] = true; names[#names + 1] = n end
    end
    add(snap.packedBy)
    for _, ev in ipairs(h) do add(ev.by) end
    return {
        id = capsuleId, state = snap.state, settled = snap.settled == true,
        script = snap.script, name = snap.name, by = snap.packedBy,
        t = tonumber(first.t) or 0, lt = tonumber(last.t) or 0, ev = last.ev,
        x = e.x, y = e.y, z = e.z, who = table.concat(names, ","),
    }
end

local FIELDS = { "state", "settled", "script", "name", "by", "t", "lt", "ev", "x", "y", "z", "who" }
local function same(a, b)
    for _, k in ipairs(FIELDS) do
        if a[k] ~= b[k] then return false end
    end
    return true
end

-- Stores the row of a snapshot just read or written (Store listener). Marks the file for the next flush.
-- Loads first: a write that lands before anyone opened the panel must not leave index.json with the old state.
function Index.put(capsuleId, snap)
    Index.load()
    local row = Index.row(capsuleId, snap)
    local old = rows[capsuleId]
    if old and same(old, row) then return end
    if not old or old.t ~= row.t then order = nil end
    rows[capsuleId] = row
    dirty = true
end

local function readText(path)
    local r = getFileReader(path, false)
    if not r then return nil end
    local lines, line = {}, r:readLine()
    while line do
        lines[#lines + 1] = line
        line = r:readLine()
    end
    r:close()
    return table.concat(lines, "\n")
end

-- Reads index.json, then reconciles it with packs/: unknown files are read (Store.read -> Index.put), rows without a
-- file are dropped. A missing or broken index therefore rebuilds itself from every file.
function Index.load()
    if rows then return end
    local text = readText(Index.FILE)
    local data = text and Json.decode(text)
    rows = {}
    if type(data) == "table" and type(data.rows) == "table" then
        for id, row in pairs(data.rows) do
            if type(id) == "number" and type(row) == "table" then rows[id] = row end
        end
    elseif text then
        M.log("index unreadable, rebuilding from snapshot files")
    end
    local names = listFilesInZomboidLuaDirectory(Store.DIR)
    local seen, missing = {}, {}
    for i = 0, (names and names:size() or 0) - 1 do
        local id = tonumber(string.match(names:get(i), "^(%-?%d+)%.json$"))
        if id then
            seen[id] = true
            if not rows[id] then missing[#missing + 1] = id end
        end
    end
    for id in pairs(rows) do
        if not seen[id] then rows[id] = nil; dirty = true end
    end
    for _, id in ipairs(missing) do Store.read(id) end -- Store.read -> listener -> Index.put
    if #missing > 0 then M.log("index added " .. #missing .. " record(s) from snapshot files") end
    order = nil
end

-- Writes index.json when something changed and FLUSH_MS has passed. Derived data: a failed write only means the next
-- start reconciles more files.
function Index.flush(now)
    if not dirty or not rows then return end
    if lastFlush and now >= lastFlush and now - lastFlush < Index.FLUSH_MS then return end
    lastFlush = now
    local text = Json.encode({ v = 1, rows = rows })
    local w = text and getFileWriter(Index.FILE, true, false)
    if not w then return end
    w:write(text)
    w:close()
    dirty = false
end

local function newestFirst(a, b)
    if a.t ~= b.t then return a.t > b.t end
    return a.id > b.id
end

local function sorted()
    if not order then
        local list = {}
        for _, row in pairs(rows) do list[#list + 1] = row end
        list = msort(list, newestFirst)
        order = {}
        for i, row in ipairs(list) do order[i] = row.id end
    end
    return order
end

function Index.uncertain(row)
    return Store.uncertain(row.id, row)
end

local function trim(s)
    s = string.gsub(tostring(s or ""), "^%s+", "")
    return string.lower((string.gsub(s, "%s+$", "")))
end

-- Matches the search text against the capsule id (substring) and every player name in its history.
local function matches(row, q)
    if q == "" then return true end
    return string.find(tostring(row.id), q, 1, true) ~= nil or string.find(row.who or "", q, 1, true) ~= nil
end

-- filter = { q = "text", state = "ALL" | "PACKED" | "UNPACKED" | "RESTORED" | "VOID" | "UNCERTAIN" }; page from 1.
-- Returns { rows, total, page, pages, counts = { ALL, PACKED, ..., UNCERTAIN } } where counts cover the search
-- result before the state filter. Rows are copies with `uncertain` filled in.
function Index.page(filter, page, size)
    Index.load()
    filter = type(filter) == "table" and filter or {}
    size = size or Index.PAGE_SIZE
    local q = trim(filter.q)
    local state = filter.state or "ALL"
    local counts = { ALL = 0, UNCERTAIN = 0 }
    for _, s in ipairs(Index.STATES) do counts[s] = 0 end
    local hits = {}
    for _, id in ipairs(sorted()) do
        local row = rows[id]
        if row and matches(row, q) then
            local unc = Index.uncertain(row)
            counts.ALL = counts.ALL + 1
            if counts[row.state] then counts[row.state] = counts[row.state] + 1 end
            if unc then counts.UNCERTAIN = counts.UNCERTAIN + 1 end
            if state == "ALL" or (state == "UNCERTAIN" and unc) or row.state == state then
                hits[#hits + 1] = row
            end
        end
    end
    local pages = math.max(1, math.ceil(#hits / size))
    page = math.max(1, math.min(pages, math.floor(tonumber(page) or 1)))
    local out = {}
    for i = (page - 1) * size + 1, math.min(#hits, page * size) do
        local r = hits[i]
        out[#out + 1] = { id = r.id, state = r.state, uncertain = Index.uncertain(r), name = r.name, script = r.script,
            by = r.by, t = r.t, lt = r.lt, ev = r.ev }
    end
    return { rows = out, total = #hits, page = page, pages = pages, counts = counts }
end

-- Test hook: forget everything in memory (the next call loads index.json again).
function Index._resetForTests()
    rows, order, dirty, lastFlush = nil, nil, false, nil
end

Store.listeners[#Store.listeners + 1] = Index.put
Events.OnTickEvenPaused.Add(function() Index.flush(getTimestampMs()) end)

return Index
