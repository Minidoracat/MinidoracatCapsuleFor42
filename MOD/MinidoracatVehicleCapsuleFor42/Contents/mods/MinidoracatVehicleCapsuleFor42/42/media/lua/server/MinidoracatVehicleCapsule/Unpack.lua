-- Vehicle Capsule: unpack a capsule into a vehicle (server authority). The snapshot is claimed (UNPACKED)
-- before the vehicle exists; any failure before the vehicle is in the world puts it back to PACKED.
-- Unpack.spawn is the one place that builds a vehicle from a snapshot (also used by Admin.restore).
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Rules"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Snapshot"
require "MinidoracatVehicleCapsule/Guard"
local M = MinidoracatVehicleCapsule
local Store, Snapshot, Guard = M.Store, M.Snapshot, M.Guard
local Unpack = {}
M.Unpack = Unpack

-- OnSpawnVehicleStart/End fire inside createPhysics, before addToWorld's trySpawnKey (BaseVehicle.java:811,904,7989-7996):
-- a restored vehicle must not drop a random key in the world.
local spawning = false
Events.OnSpawnVehicleEnd.Add(function(vehicle)
    if spawning then vehicle:setPreviouslyMoved(true) end
end)

-- Server-side lookup by id: the player's inventory (recursive), then ground items within PACK_RANGE.
function Unpack.findCapsule(player, capsuleId)
    local item = player:getInventory():getItemWithIDRecursiv(capsuleId)
    if item then return item end
    local cell, r = getCell(), M.PACK_RANGE
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            local objs = sq and sq:getWorldObjects()
            if objs then
                for i = 0, objs:size() - 1 do
                    local it = objs:get(i):getItem()
                    if it and it:getID() == capsuleId then return it end
                end
            end
        end
    end
    return nil
end

-- Removes the capsule wherever it is and tells clients.
local function removeCapsule(player, capsule)
    local wo = capsule:getWorldItem()
    if wo and wo:getSquare() then
        wo:getSquare():transmitRemoveItemFromSquare(wo)
        capsule:setWorldItem(nil)
        return
    end
    local c = capsule:getContainer()
    if c then
        player:removeFromHands(capsule)
        c:DoRemoveItem(capsule)
        sendRemoveItemFromContainer(c, capsule)
    end
end

-- Spawns snap's vehicle on square and writes the snapshot back in the same tick. With `capsule` its cargo goes back
-- into the part containers; without (admin restore) the containers stay empty.
-- opts.transmit: flag every transmit* after the restore (test knob).
-- opts.persist (default true): queue a vehicles.db UPDATE right away; addVehicleDebug INSERTed the random spawn state.
-- Returns vehicle, cargo { home, other, ground } or nil, why ("CORRUPT" / "SCRIPT_MISSING" / "BLOCKED").
function Unpack.spawn(snap, square, dir, opts, capsule)
    opts = opts or {}
    local bad = Snapshot.missing(snap)
    if bad then
        M.log("snapshot missing " .. bad .. ", not spawning")
        return nil, "CORRUPT"
    end
    if not getScriptManager():getVehicle(snap.script) then return nil, "SCRIPT_MISSING" end
    if not square then return nil, "BLOCKED" end
    spawning = true
    local ok, vehicle = pcall(addVehicleDebug, snap.script, IsoDirections[dir or "N"] or IsoDirections.N, nil, square)
    spawning = false
    -- addVehicleDebug returns a vehicle even when the spot is invalid (LuaManager.java:10817-10826)
    if not ok or not vehicle or not vehicle:getSquare() then
        if not ok then M.log("addVehicleDebug failed: " .. tostring(vehicle)) end
        return nil, "BLOCKED"
    end
    Snapshot.restore(vehicle, snap, opts)
    local cargo = { home = 0, other = 0, ground = 0 }
    if capsule then cargo = Snapshot.restoreCargo(capsule, vehicle, snap) end
    if opts.persist ~= false then vehicle:exit(nil) end -- exit(null) only runs VehiclesDB2.updateVehicleAndTrailer (BaseVehicle.java:2543-2549)
    return vehicle, cargo
end

-- Returns { ok = true, vehicleId, sqlId, returned, script, ... } or { ok = false, why }. A capsule whose record is
-- stale (its cargo is a second copy) is replaced by an empty one: why = "CLEARED". An empty capsule goes back to the
-- player when SandboxVars ReturnEmptyCapsule is on (returned = true).
function Unpack.unpack(player, capsule, square, dir, opts)
    local capsuleId = capsule:getID()
    local snap, why, stale = Store.claim(capsuleId, player)
    if why == "STALE" then
        Guard.clear(player, capsule, capsuleId, stale, "unpack")
        return { ok = false, why = "CLEARED" }
    end
    if not snap then return { ok = false, why = why } end
    local vehicle, cargo = Unpack.spawn(snap, square, dir, opts, capsule)
    if not vehicle then
        Store.release(capsuleId, snap, player, cargo)
        return { ok = false, why = cargo }
    end
    removeCapsule(player, capsule)
    local inv = player:getInventory()
    local empty = M.Rules.sandbox().ReturnEmptyCapsule ~= false and instanceItem(M.ITEM_EMPTY)
    if empty then
        inv:AddItem(empty)
        sendAddItemToContainer(inv, empty)
    end
    local sq = vehicle:getSquare()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    Store.event(capsuleId, snap, "UNPACKED", player, { x = x, y = y, z = z, car = vehicle:getSqlId() })
    return {
        ok = true, capsuleId = capsuleId, vehicleId = vehicle:getId(), sqlId = vehicle:getSqlId(),
        x = x, y = y, z = z, keyId = vehicle:getKeyId(), skin = vehicle:getSkinIndex(),
        home = cargo.home, other = cargo.other, ground = cargo.ground, returned = empty ~= nil and empty ~= false,
        script = snap.script,
    }
end

return Unpack
