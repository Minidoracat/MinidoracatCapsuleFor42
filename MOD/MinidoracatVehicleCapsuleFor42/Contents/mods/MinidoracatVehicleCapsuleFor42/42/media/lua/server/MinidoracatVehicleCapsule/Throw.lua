-- Vehicle Capsule: a thrown or pressed capsule lands (server authority; SP runs the same code locally).
-- The action's complete() schedules the landing; the capsule stays where it is (inventory or ground) until then.
-- Landing: a record that is not a usable PACKED one goes straight to Unpack (it refuses, logs and clears stale cargo);
-- otherwise the footprint must be clear, then Unpack spawns the vehicle. A blocked throw drops the capsule on the
-- landing square; a pressed capsule stays where it lies.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Footprint"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Unpack"
require "MinidoracatVehicleCapsule/Fx"
local M = MinidoracatVehicleCapsule
local Footprint, Store, Unpack, Fx = M.Footprint, M.Store, M.Unpack, M.Fx
local Throw = { pending = {} }
M.Throw = Throw

Throw.FLIGHT_MS = 500

-- Still connected (a player who left during the flight keeps the capsule; their inventory is already saved).
local function online(player)
    if not isServer() then return true end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        if players:get(i) == player then return true end
    end
    return false
end

-- When the record left PACKED (unpack, admin restore or verdict), for the "already unpacked" dialog.
local LEFT_PACKED = { UNPACKED = true, RESTORE_START = true, RESTORED = true, RESOLVED = true }
local function stateTime(snap)
    for i = #(snap.history or {}), 1, -1 do
        local e = snap.history[i]
        if LEFT_PACKED[e.ev] then return e.t end
    end
    return nil
end

local function dropAt(player, capsule, sq)
    local c = capsule:getContainer()
    if not c or capsule:getWorldItem() then return false end
    player:removeFromHands(capsule)
    c:DoRemoveItem(capsule)
    sendRemoveItemFromContainer(c, capsule)
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0)
    return true
end

-- p = { player, capsuleId, x, y, z, dir, mode = "throw" | "press" }
function Throw.land(p)
    local player = p.player
    if not online(player) then
        M.log("land skipped capsule=" .. p.capsuleId .. ": thrower left")
        return
    end
    local res
    local capsule = Unpack.findCapsule(player, p.capsuleId)
    local sq = getCell():getGridSquare(p.x, p.y, p.z)
    if not capsule then
        res = { ok = false, why = "NO_CAPSULE" }
    else
        local snap = Store.read(p.capsuleId)
        local usable = snap and snap.state == "PACKED" and not Store.uncertain(p.capsuleId, snap)
        local reason = usable and Footprint.clear(getScriptManager():getVehicle(snap.script), p.x, p.y, p.z, p.dir)
        if reason and reason ~= "NO_SCRIPT" then
            res = { ok = false, why = "BLOCKED", reason = reason }
        else
            res = Unpack.unpack(player, capsule, sq, p.dir, {})
            if res.why == "BLOCKED" then res.reason = "SPAWN" end
        end
        if not res.ok and res.why ~= "BLOCKED" then
            snap = Store.read(p.capsuleId)
            if snap then res.state, res.t = snap.state, stateTime(snap) end
        end
        if res.why == "BLOCKED" and p.mode == "throw" and sq then res.dropped = dropAt(player, capsule, sq) end
    end
    res.capsuleId, res.mode = p.capsuleId, p.mode
    if res.ok then Fx.broadcast("unpack", { x = p.x, y = p.y, z = p.z }) end
    M.log(string.format("LANDED capsule=%d by=%s mode=%s x=%d y=%d z=%d dir=%s ok=%s why=%s reason=%s dropped=%s",
        p.capsuleId, player:getUsername(), p.mode, p.x, p.y, p.z, tostring(p.dir), tostring(res.ok),
        tostring(res.why), tostring(res.reason), tostring(res.dropped)))
    M.Play.send(player, "landed", res)
end

-- Lands p at getTimestampMs() >= at.
function Throw.schedule(p, at)
    p.at = at
    Throw.pending[#Throw.pending + 1] = p
end

Events.OnTick.Add(function()
    if #Throw.pending == 0 then return end
    local now, due = getTimestampMs(), nil
    for i = #Throw.pending, 1, -1 do
        if Throw.pending[i].at <= now then
            due = due or {}
            table.insert(due, 1, table.remove(Throw.pending, i))
        end
    end
    if not due then return end
    for _, p in ipairs(due) do
        local ok, err = pcall(Throw.land, p)
        if not ok then M.log("land failed capsule=" .. tostring(p.capsuleId) .. ": " .. tostring(err)) end
    end
end)

return Throw
