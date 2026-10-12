-- Universal Capsule: pack a parked vehicle into a capsule (server authority, fixed order; delete the car last).
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Store"
require "MinidoracatCapsule/Snapshot"
require "MinidoracatCapsule/Fx"
local M = MinidoracatCapsule
local Store, Snapshot = M.Store, M.Snapshot
local Pack = {}
M.Pack = Pack

-- Reason code why this vehicle cannot be packed right now, or nil (player rules: Rules.packWhyNot).
Pack.whyNot = M.Rules.vehicleWhyNot

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
    sq:AddWorldInventoryItem(capsule, 0.5, 0.5, 0) -- transmits the whole item (contents included) to clients
    vehicle:permanentlyRemove()
    M.Fx.broadcast("pack", { x = x, y = y, z = z, style = t.index })
    local line = M.LOG_PREFIX .. "PACKED capsule=" .. capsuleId .. " state=PACKED by=" .. snap.packedBy
        .. " x=" .. x .. " y=" .. y .. " z=" .. z .. " car=" .. tostring(car) .. " script=" .. tostring(snap.script)
        .. " type=" .. t.id
        .. " cargo=" .. moved .. " key=" .. tostring(key ~= nil) .. " empty=" .. tostring(empty ~= nil)
        .. " skipped=" .. (#snap.skipped > 0 and table.concat(snap.skipped, ",") or "-")
    writeLog("UniversalCapsule", line)
    print(line)
    return { ok = true, capsuleId = capsuleId, x = x, y = y, z = z, cargo = moved,
        skipped = table.concat(snap.skipped, ","), script = snap.script, type = t.id }
end

return Pack
