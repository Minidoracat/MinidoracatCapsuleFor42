-- Vehicle Capsule: server snapshot files, Zomboid/Lua/MinidoracatVehicleCapsule/packs/<capsuleId>.json.
-- The file is the only source of truth for a capsule. States:
--   PACKED   -> UNPACKED (unpack) | RESTORED (admin restore) | VOID (admin: the original car is still there)
--   UNPACKED -> PACKED (spawn failed, or admin: the new car is gone) | RESTORED (admin, uncertain records only)
-- Every change that touched vehicles.db is marked `settled` SETTLE_MS later. A record without it that is not
-- pending in this server run was cut short by a crash: "uncertain", unpack refuses it until an admin resolves it.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Json"
local M = MinidoracatVehicleCapsule
local Json = M.Json
local Store = {}
M.Store = Store

Store.DIR = "MinidoracatVehicleCapsule/packs/"
-- vehicles.db INSERT/UPDATE/DELETE commit on the SPV thread about every 500 ms (VehiclesDB2.java:327-331,879-889).
Store.SETTLE_MS = 5000

local pending = {} -- capsuleId -> ms when it settles; this server run only
local status = {}  -- capsuleId -> { state, settled, sealed } or false (no readable file); kept fresh by read/write
local warned = {}  -- capsuleId -> true once its uncertain record was logged in this server run

function Store.path(capsuleId)
    return Store.DIR .. tostring(capsuleId) .. ".json"
end

local function readText(path)
    local r = getFileReader(path, false)
    if not r then return nil end
    local lines = {}
    local line = r:readLine()
    while line do
        lines[#lines + 1] = line
        line = r:readLine()
    end
    r:close()
    return table.concat(lines, "\n")
end

-- fn(capsuleId, snap, written) after every successful read (written = false) and write (written = true): the admin
-- index follows both, the query cache invalidation only writes. A failing listener never breaks the Store.
Store.listeners = {}

local function remember(capsuleId, snap, written)
    status[capsuleId] = { state = snap.state, settled = snap.settled == true, sealed = snap.sealed }
    for _, fn in ipairs(Store.listeners) do
        local ok, err = pcall(fn, capsuleId, snap, written)
        if not ok then M.log("store listener failed: " .. tostring(err)) end
    end
end

-- Unsettled and not waiting to settle in this run: written right before a crash. VOID is final either way.
-- Works on a snapshot and on a Store.status entry.
function Store.uncertain(capsuleId, snap)
    return snap.state ~= "VOID" and snap.settled ~= true and pending[capsuleId] == nil
end

-- The capsule's cargo is a second copy: the spawned car was committed with it (UNPACKED, settled) or the original
-- car never left (VOID). Works on a snapshot and on a Store.status entry.
function Store.isStale(snap)
    return snap.state == "VOID" or (snap.state == "UNPACKED" and snap.settled == true)
end

-- Returns snap, or nil plus "NO_SNAPSHOT" / "CORRUPT". The first uncertain read of a run is logged for admins.
-- A record whose last event is newer than two settle windows is being written right now (the index reloads inside
-- Store.write before the caller schedules the settle), not a crash leftover: no log for it.
function Store.read(capsuleId)
    local text = readText(Store.path(capsuleId))
    if not text then return nil, "NO_SNAPSHOT" end
    local snap, err = Json.decode(text)
    if type(snap) ~= "table" then
        M.log("snapshot " .. tostring(capsuleId) .. " unreadable: " .. tostring(err))
        return nil, "CORRUPT"
    end
    remember(capsuleId, snap)
    if Store.uncertain(capsuleId, snap) and not warned[capsuleId] then
        local h = snap.history
        local last = h and h[#h] and tonumber(h[#h].t) or 0
        if getTimestampMs() - last > 2 * Store.SETTLE_MS then
            warned[capsuleId] = true
            local line = M.LOG_PREFIX .. "UNCERTAIN capsule=" .. tostring(capsuleId) .. " state=" .. tostring(snap.state)
                .. " (written right before a crash; an admin has to resolve it)"
            writeLog("VehicleCapsule", line)
            print(line)
        end
    end
    return snap
end

-- Cached { state, settled, sealed } for the guard's scans: the file is read once, then every write refreshes it.
-- false when there is no readable snapshot.
function Store.status(capsuleId)
    local st = status[capsuleId]
    if st == nil then
        if not Store.read(capsuleId) then status[capsuleId] = false end
        st = status[capsuleId]
    end
    return st
end

-- Writes the whole snapshot and reads it back. Returns true, or nil plus a reason
-- ("MODDATA_UNSUPPORTED" with the bad path, or "WRITE_FAILED"). getFileWriter swallows I/O errors.
function Store.write(capsuleId, snap)
    local text, bad = Json.encode(snap)
    if not text then return nil, "MODDATA_UNSUPPORTED", bad end
    local path = Store.path(capsuleId)
    local w = getFileWriter(path, true, false)
    if not w then return nil, "WRITE_FAILED" end
    local ok = pcall(function()
        w:write(text)
        w:close()
    end)
    if not ok or readText(path) ~= text then
        M.log("snapshot " .. tostring(capsuleId) .. " write did not read back")
        return nil, "WRITE_FAILED"
    end
    remember(capsuleId, snap, true)
    return true
end

-- The record settles SETTLE_MS from now (pack, unpack, restore, release).
function Store.schedule(capsuleId)
    pending[capsuleId] = getTimestampMs() + Store.SETTLE_MS
end

-- Writes settled = true (read back). It leaves `pending` either way: a record that could not be marked is uncertain.
function Store.settle(capsuleId)
    local snap, why = Store.read(capsuleId)
    pending[capsuleId] = nil
    if not snap then
        M.log("settle " .. tostring(capsuleId) .. " failed: " .. tostring(why))
        return nil, why
    end
    if snap.settled == true then return true end
    snap.settled = true
    local ok, werr = Store.write(capsuleId, snap)
    if not ok then
        M.log("settle " .. tostring(capsuleId) .. " failed: " .. tostring(werr))
        return nil, werr
    end
    print(M.LOG_PREFIX .. "SETTLED capsule=" .. tostring(capsuleId) .. " state=" .. tostring(snap.state))
    return true
end

-- Settles every record that is due. Called every tick (Guard.lua).
function Store.settleDue(now)
    local due
    for id, at in pairs(pending) do
        if at <= now then
            due = due or {}
            due[#due + 1] = id
        end
    end
    if not due then return end
    for _, id in ipairs(due) do Store.settle(id) end
end

local function where(player, info)
    local e = { t = getTimestampMs(), by = player and player:getUsername() or "-" }
    if info then
        for k, v in pairs(info) do e[k] = v end
    end
    if e.x == nil and player then
        e.x, e.y, e.z = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    end
    return e
end

local function logEvent(capsuleId, e, state)
    local line = M.LOG_PREFIX .. e.ev .. " capsule=" .. tostring(capsuleId) .. " state=" .. tostring(state)
        .. " by=" .. tostring(e.by) .. " x=" .. tostring(e.x) .. " y=" .. tostring(e.y) .. " z=" .. tostring(e.z)
        .. " car=" .. tostring(e.car)
    for _, k in ipairs({ "why", "verdict", "items", "note" }) do
        if e[k] ~= nil then line = line .. " " .. k .. "=" .. tostring(e[k]) end
    end
    writeLog("VehicleCapsule", line)
    print(line)
end

-- Appends a history entry to snap (in memory) and writes the file. info: x, y, z, car, why, verdict, items, note.
function Store.event(capsuleId, snap, ev, player, info)
    local e = where(player, info)
    e.ev = ev
    snap.history = snap.history or {}
    snap.history[#snap.history + 1] = e
    local ok, why = Store.write(capsuleId, snap)
    logEvent(capsuleId, e, snap.state)
    return ok, why
end

local ALLOWED = {
    PACKED = { UNPACKED = true, RESTORED = true, VOID = true },
    UNPACKED = { PACKED = true, RESTORED = true },
}

-- Allowed transitions only; anything else is refused without touching the file. The history entry is `info.ev`
-- or the new state. The new state settles in SETTLE_MS unless `settled` (an admin verdict moves no vehicle).
function Store.setState(capsuleId, snap, to, player, info, settled)
    if not (ALLOWED[snap.state] and ALLOWED[snap.state][to]) then return nil, "BAD_TRANSITION" end
    snap.state = to
    snap.settled = settled and true or nil
    local ok, why = Store.event(capsuleId, snap, info and info.ev or to, player, info)
    if ok then
        if settled then pending[capsuleId] = nil else Store.schedule(capsuleId) end
    end
    return ok, why
end

-- Unpack may only start from a PACKED record that is not uncertain; it is marked UNPACKED before the vehicle exists.
-- Returns snap, or nil plus a reason:
--   "STALE" (+ snap): the capsule's cargo is a second copy, the caller clears the capsule (Guard.clear);
--   "UNCERTAIN" / "NOT_PACKED": REJECTED event, the capsule is left alone (its cargo may be the only copy).
function Store.claim(capsuleId, player)
    local snap, why = Store.read(capsuleId)
    if not snap then return nil, why end
    if Store.isStale(snap) then return nil, "STALE", snap end
    local uncertain = Store.uncertain(capsuleId, snap)
    if snap.state ~= "PACKED" or uncertain then
        why = uncertain and "UNCERTAIN" or "NOT_PACKED"
        Store.event(capsuleId, snap, "REJECTED", player, { why = why })
        return nil, why
    end
    snap.state = "UNPACKED"
    snap.settled = nil
    local ok, werr = Store.write(capsuleId, snap)
    if not ok then return nil, werr end
    Store.schedule(capsuleId)
    return snap
end

-- A spawn that did not happen is undone: state and settled go back to `prev` = { state, settled, uncertain }, with
-- event `ev` and the reason in history. An uncertain record stays uncertain; a pending one settles again.
function Store.undo(capsuleId, snap, prev, player, ev, why)
    snap.state = prev.state
    snap.settled = prev.settled and true or nil
    pending[capsuleId] = nil
    local ok, werr = Store.event(capsuleId, snap, ev, player, { why = why })
    if ok and not prev.settled and not prev.uncertain then Store.schedule(capsuleId) end
    return ok, werr
end

-- Unpack spawn failed after claim: back to PACKED with the reason in history.
function Store.release(capsuleId, snap, player, why)
    if snap.state ~= "UNPACKED" then return nil, "BAD_TRANSITION" end
    return Store.undo(capsuleId, snap, { state = "PACKED" }, player, "UNPACK_FAILED", why)
end

return Store
