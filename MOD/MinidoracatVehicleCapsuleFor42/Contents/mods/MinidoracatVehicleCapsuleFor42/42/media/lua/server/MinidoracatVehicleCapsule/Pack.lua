-- Vehicle Capsule: pack a parked vehicle into a capsule (server authority, fixed order; delete the car last).
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Snapshot"
local M = MinidoracatVehicleCapsule
local Store, Snapshot = M.Store, M.Snapshot
local Pack = {}
M.Pack = Pack

local function dist(player, x, y)
    local dx, dy = player:getX() - x, player:getY() - y
    return math.sqrt(dx * dx + dy * dy)
end

-- Reason code why this vehicle cannot be packed right now, or nil.
function Pack.whyNot(player, vehicle)
    if not vehicle or not vehicle:getSquare() then return "NO_VEHICLE" end
    if dist(player, vehicle:getX(), vehicle:getY()) > M.PACK_RANGE then return "TOO_FAR" end
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(seat) then return "OCCUPIED" end
    end
    if vehicle:getVehicleTowing() or vehicle:getVehicleTowedBy() then return "TOWING" end
    local animals = vehicle:getAnimals()
    if animals and animals:size() > 0 then return "ANIMALS" end
    if vehicle:isEngineRunning() then return "ENGINE_RUNNING" end
    for i = 0, vehicle:getPartCount() - 1 do
        local inv = vehicle:getPartByIndex(i):getItemContainer()
        if inv and inv:containsTypeRecurse(M.ITEM_LOADED) then return "CAPSULE_INSIDE" end
    end
    return nil
end

-- Returns { ok = true, capsuleId, name, x, y, z } or { ok = false, why, path? }.
function Pack.pack(player, vehicle)
    local why = Pack.whyNot(player, vehicle)
    if why then return { ok = false, why = why } end
    local sq = vehicle:getSquare()
    local x, y, z = sq:getX(), sq:getY(), sq:getZ()
    local car = vehicle:getSqlId()

    local snap = Snapshot.capture(vehicle)
    local capsule = instanceItem(M.ITEM_LOADED)
    if not capsule then return { ok = false, why = "NO_ITEM" } end
    local capsuleId = capsule:getID()
    snap.state = "PACKED"
    snap.packedBy = player:getUsername()
    snap.history = { { t = getTimestampMs(), ev = "PACKED", by = snap.packedBy, x = x, y = y, z = z, car = car } }
    local ok, werr, path = Store.write(capsuleId, snap)
    if not ok then
        M.log("pack refused " .. tostring(werr) .. " " .. tostring(path or ""))
        return { ok = false, why = werr, path = path }
    end
    -- From here the snapshot is on disk; move things, delete the car last.
    local moved = Snapshot.packCargo(vehicle, capsule, snap)
    local key = vehicle:getCurrentKey()
    if key then
        local inv = player:getInventory()
        inv:AddItem(key) -- also removes it from the ignition container
        sendAddItemToContainer(inv, key)
        vehicle:setCurrentKey(nil)
        vehicle:setKeysInIgnition(false)
    end
    local name = getText("IGUI_MinidoracatVehicleCapsule_LoadedName", snap.name)
    capsule:setName(name)
    capsule:setCustomName(true)
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0) -- transmits the whole item (name, contents) to clients
    vehicle:permanentlyRemove()
    local line = M.LOG_PREFIX .. "PACKED capsule=" .. capsuleId .. " state=PACKED by=" .. snap.packedBy
        .. " x=" .. x .. " y=" .. y .. " z=" .. z .. " car=" .. tostring(car) .. " script=" .. tostring(snap.script)
        .. " cargo=" .. moved .. " key=" .. tostring(key ~= nil)
        .. " skipped=" .. (#snap.skipped > 0 and table.concat(snap.skipped, ",") or "-")
    writeLog("VehicleCapsule", line)
    print(line)
    return { ok = true, capsuleId = capsuleId, name = name, x = x, y = y, z = z, cargo = moved,
        skipped = table.concat(snap.skipped, ",") }
end

return Pack
