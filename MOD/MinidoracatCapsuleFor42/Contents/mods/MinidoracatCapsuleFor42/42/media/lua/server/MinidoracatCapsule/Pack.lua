-- Universal Capsule: pack a parked vehicle or a live animal into a capsule (server authority, fixed order; the vehicle
-- or the animal goes last).
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Store"
require "MinidoracatCapsule/Snapshot"
require "MinidoracatCapsule/Animal"
require "MinidoracatCapsule/Fx"
local M = MinidoracatCapsule
local Store, Snapshot = M.Store, M.Snapshot
local Pack = {}
M.Pack = Pack

-- Reason code why this vehicle cannot be packed right now, or nil (player rules: Rules.packWhyNot).
Pack.whyNot = M.Rules.vehicleWhyNot

-- The player's empty capsule is used up (the record is already on disk).
local function useUp(player, item)
    local c = item and item:getContainer()
    if not c then return false end
    player:removeFromHands(item)
    c:DoRemoveItem(item)
    sendRemoveItemFromContainer(c, item)
    return true
end

local function writeLine(line)
    writeLog("UniversalCapsule", line)
    print(line)
end

-- opts.type: the capsule type (M.TYPES row) of opts.empty, the player's empty capsule, used up once the snapshot is on
-- disk; without them (debug commands) a cartoon capsule and nothing used up. The capsule keeps the script's name: each
-- client names it in its own language from the record (client/Info.lua), so no packing client's language sticks.
-- Returns { ok = true, capsuleId, x, y, z, ... } or { ok = false, why, path? }.
function Pack.pack(player, vehicle, opts)
    opts = opts or {}
    local why = Pack.whyNot(player, vehicle)
    if why then return { ok = false, why = why } end
    local sq = vehicle:getSquare()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local car = vehicle:getSqlId()

    local snap = Snapshot.capture(vehicle)
    local t = opts.type or M.TYPES[1]
    local capsule = instanceItem(t.loaded)
    if not capsule then return { ok = false, why = "NO_ITEM" } end
    local capsuleId = capsule:getID()
    snap.state = "PACKED"
    snap.packedBy = player:getUsername()
    snap.history = { { t = getTimestampMs(), ev = "PACKED", by = snap.packedBy, x = x, y = y, z = z, car = car } }
    snap.seen = { t = snap.history[1].t, where = "ground", x = x, y = y, z = z } -- the capsule drops where the car stood
    local ok, werr, path = Store.write(capsuleId, snap)
    if not ok then
        M.log("pack refused " .. tostring(werr) .. " " .. tostring(path or ""))
        return { ok = false, why = werr, path = path }
    end
    -- From here the snapshot is on disk; move things, delete the car last. Settles once the DELETE is committed.
    Store.schedule(capsuleId)
    local empty = useUp(player, opts.empty)
    local moved = Snapshot.packCargo(vehicle, capsule, snap)
    local key = vehicle:getCurrentKey()
    if key then
        local inv = player:getInventory()
        inv:AddItem(key) -- also removes it from the ignition container
        sendAddItemToContainer(inv, key)
        vehicle:setCurrentKey(nil)
        vehicle:setKeysInIgnition(false)
    end
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0) -- transmits the whole item (contents included) to clients
    vehicle:permanentlyRemove()
    M.Fx.broadcast("pack", { x = x, y = y, z = z, style = t.index })
    writeLine(M.LOG_PREFIX .. "PACKED capsule=" .. capsuleId .. " state=PACKED by=" .. snap.packedBy
        .. " x=" .. x .. " y=" .. y .. " z=" .. z .. " car=" .. tostring(car) .. " script=" .. tostring(snap.script)
        .. " type=" .. t.id
        .. " cargo=" .. moved .. " key=" .. tostring(key ~= nil) .. " empty=" .. tostring(empty)
        .. " skipped=" .. (#snap.skipped > 0 and table.concat(snap.skipped, ",") or "-"))
    return { ok = true, capsuleId = capsuleId, x = x, y = y, z = z, cargo = moved,
        skipped = table.concat(snap.skipped, ","), script = snap.script, type = t.id }
end

-- Packs a live animal: the record is { kind = "animal", animal = Animal.capture(...) } and the loaded capsule (empty
-- inside, the animal lives only in the record) drops on the animal's square. The menu action (Play.packAnimal) and a
-- thrown empty capsule share this. opts.capsule: the player's empty capsule, already checked by the caller (used up
-- once the record is on disk; none for debug); opts.typeId: its M.TYPES id (default the first type).
-- Like vanilla picking up (ISPickupAnimal.complete), a wild animal of a kind that can be tamed becomes tame
-- (setWild(false) is a no-op for the others, IsoAnimal.java:3214-3225). The animal is removed last, once record and
-- capsule are in place (IsoAnimal.remove deletes it and tells every client).
-- Returns the vehicle result shape: { ok = true, capsuleId, x, y, z, type, kind = "animal", animal = { type, breed,
-- name } } or { ok = false, why, path? }.
function Pack.packAnimal(player, animal, opts)
    opts = opts or {}
    local why = M.Rules.animalWhyNot(player, animal)
    if why then return { ok = false, why = why } end
    local t = M.TYPE_BY_ID[tostring(opts.typeId)] or M.TYPES[1]
    local capsule = instanceItem(t.loaded)
    if not capsule then return { ok = false, why = "NO_ITEM" } end
    local capsuleId = capsule:getID()
    local sq = animal:getSquare()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    animal:setWild(false)
    local a = M.Animal.capture(animal, player)
    local by = player:getUsername()
    local now = getTimestampMs()
    local snap = { kind = "animal", animal = a, state = "PACKED", packedBy = by,
        history = { { t = now, ev = "PACKED", by = by, x = x, y = y, z = z, animal = a.animalId } },
        seen = { t = now, where = "ground", x = x, y = y, z = z } }
    local ok, werr, path = Store.write(capsuleId, snap)
    if not ok then
        M.log("pack animal refused " .. tostring(werr) .. " " .. tostring(path or ""))
        return { ok = false, why = werr, path = path }
    end
    Store.schedule(capsuleId)
    local empty = useUp(player, opts.capsule)
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0)
    animal:remove()
    M.Fx.broadcast("pack", { x = x, y = y, z = z, style = t.index })
    writeLine(M.LOG_PREFIX .. "PACKED capsule=" .. capsuleId .. " state=PACKED by=" .. by .. " x=" .. x .. " y=" .. y
        .. " z=" .. z .. " kind=animal animal=" .. tostring(a.animalId) .. " animalType=" .. tostring(a.type)
        .. " breed=" .. tostring(a.breed) .. " name=" .. tostring(a.name) .. " wild=" .. tostring(a.wild)
        .. " type=" .. t.id .. " empty=" .. tostring(empty))
    return { ok = true, capsuleId = capsuleId, x = x, y = y, z = z, type = t.id, kind = "animal",
        animal = { type = a.type, breed = a.breed, name = a.name } }
end

return Pack
