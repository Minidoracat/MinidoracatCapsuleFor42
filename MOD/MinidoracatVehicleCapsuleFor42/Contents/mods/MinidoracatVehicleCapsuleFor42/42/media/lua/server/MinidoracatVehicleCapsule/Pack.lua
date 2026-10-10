-- Vehicle Capsule: pack a parked vehicle into a capsule (server authority, fixed order; delete the car last).
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Rules"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Snapshot"
require "MinidoracatVehicleCapsule/Fx"
local M = MinidoracatVehicleCapsule
local Store, Snapshot = M.Store, M.Snapshot
local Pack = {}
M.Pack = Pack

-- Reason code why this vehicle cannot be packed right now, or nil (player rules: Rules.packWhyNot).
Pack.whyNot = M.Rules.vehicleWhyNot

-- opts.name: capsule name composed by the packing client in its language (already Rules.cleanName'd); without it
-- (debug commands) the server composes one in its own language. opts.empty: the player's empty capsule, used up
-- once the snapshot is on disk.
-- Returns { ok = true, capsuleId, name, x, y, z } or { ok = false, why, path? }.
function Pack.pack(player, vehicle, opts)
    opts = opts or {}
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
    snap.seen = { t = snap.history[1].t, where = "ground", x = x, y = y, z = z } -- the capsule drops where the car stood
    local ok, werr, path = Store.write(capsuleId, snap)
    if not ok then
        M.log("pack refused " .. tostring(werr) .. " " .. tostring(path or ""))
        return { ok = false, why = werr, path = path }
    end
    -- From here the snapshot is on disk; move things, delete the car last. Settles once the DELETE is committed.
    Store.schedule(capsuleId)
    local empty = opts.empty and opts.empty:getContainer()
    if empty then
        player:removeFromHands(opts.empty)
        empty:DoRemoveItem(opts.empty)
        sendRemoveItemFromContainer(empty, opts.empty)
    end
    local moved = Snapshot.packCargo(vehicle, capsule, snap)
    local key = vehicle:getCurrentKey()
    if key then
        local inv = player:getInventory()
        inv:AddItem(key) -- also removes it from the ignition container
        sendAddItemToContainer(inv, key)
        vehicle:setCurrentKey(nil)
        vehicle:setKeysInIgnition(false)
    end
    local name = opts.name or getText("IGUI_MinidoracatVehicleCapsule_LoadedName", snap.name)
    capsule:setName(name)
    capsule:setCustomName(true)
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0) -- transmits the whole item (name, contents) to clients
    vehicle:permanentlyRemove()
    M.Fx.broadcast("pack", { x = x, y = y, z = z })
    local line = M.LOG_PREFIX .. "PACKED capsule=" .. capsuleId .. " state=PACKED by=" .. snap.packedBy
        .. " x=" .. x .. " y=" .. y .. " z=" .. z .. " car=" .. tostring(car) .. " script=" .. tostring(snap.script)
        .. " cargo=" .. moved .. " key=" .. tostring(key ~= nil) .. " empty=" .. tostring(empty ~= nil)
        .. " skipped=" .. (#snap.skipped > 0 and table.concat(snap.skipped, ",") or "-")
    writeLog("VehicleCapsule", line)
    print(line)
    return { ok = true, capsuleId = capsuleId, name = name, x = x, y = y, z = z, cargo = moved,
        skipped = table.concat(snap.skipped, ","), script = snap.script }
end

return Pack
