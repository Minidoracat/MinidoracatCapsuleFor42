-- Vehicle Capsule: server snapshot files, Zomboid/Lua/MinidoracatVehicleCapsule/packs/<capsuleId>.json.
-- The file is the only source of truth for a capsule; state goes PACKED -> UNPACKED or PACKED -> RESTORED once.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Json"
local M = MinidoracatVehicleCapsule
local Json = M.Json
local Store = {}
M.Store = Store

Store.DIR = "MinidoracatVehicleCapsule/packs/"

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

-- Returns snap, or nil plus "NO_SNAPSHOT" / "CORRUPT".
function Store.read(capsuleId)
    local text = readText(Store.path(capsuleId))
    if not text then return nil, "NO_SNAPSHOT" end
    local snap, err = Json.decode(text)
    if type(snap) ~= "table" then
        M.log("snapshot " .. tostring(capsuleId) .. " unreadable: " .. tostring(err))
        return nil, "CORRUPT"
    end
    return snap
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
    return true
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
        .. " car=" .. tostring(e.car) .. (e.why and (" why=" .. tostring(e.why)) or "")
    writeLog("VehicleCapsule", line)
    print(line)
end

-- Appends a history entry to snap (in memory) and writes the file. info: x, y, z, car, why.
function Store.event(capsuleId, snap, ev, player, info)
    local e = where(player, info)
    e.ev = ev
    snap.history = snap.history or {}
    snap.history[#snap.history + 1] = e
    local ok, why = Store.write(capsuleId, snap)
    logEvent(capsuleId, e, snap.state)
    return ok, why
end

local ALLOWED = { PACKED = { UNPACKED = true, RESTORED = true } }

-- The only forward transitions; anything else is refused without touching the file.
function Store.setState(capsuleId, snap, to, player, info)
    if not (ALLOWED[snap.state] and ALLOWED[snap.state][to]) then return nil, "BAD_TRANSITION" end
    snap.state = to
    return Store.event(capsuleId, snap, to, player, info)
end

-- Marks the capsule UNPACKED before the vehicle is spawned. Not PACKED -> REJECTED event, "NOT_PACKED".
function Store.claim(capsuleId, player)
    local snap, why = Store.read(capsuleId)
    if not snap then return nil, why end
    if snap.state ~= "PACKED" then
        Store.event(capsuleId, snap, "REJECTED", player, { why = tostring(snap.state) })
        return nil, "NOT_PACKED"
    end
    snap.state = "UNPACKED"
    local ok, werr = Store.write(capsuleId, snap)
    if not ok then return nil, werr end
    return snap
end

-- Spawn failed after claim: back to PACKED (the one allowed step back) with the reason in history.
function Store.release(capsuleId, snap, player, why)
    if snap.state ~= "UNPACKED" then return nil, "BAD_TRANSITION" end
    snap.state = "PACKED"
    return Store.event(capsuleId, snap, "UNPACK_FAILED", player, { why = why })
end

return Store
