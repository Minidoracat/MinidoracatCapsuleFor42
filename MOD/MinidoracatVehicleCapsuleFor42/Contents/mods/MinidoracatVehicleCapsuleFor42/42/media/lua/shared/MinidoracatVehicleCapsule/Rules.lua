-- Vehicle Capsule: player rules shared by the client menus (what the tooltip rows show) and the server actions
-- (what complete() enforces). The client copy only decides the menu; the server checks again before anything moves.
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule
local Rules = {}
M.Rules = Rules

Rules.PACK_SECONDS = 10
Rules.THROW_RANGE = 8 -- tiles from the thrower to the landing point
Rules.PRESS_RANGE = 3 -- tiles from a capsule on the ground to the landing point

function Rules.sandbox()
    return SandboxVars and SandboxVars.MinidoracatVehicleCapsule or {}
end

-- Sandbox AllowCargoTakeOut: cargo may leave a loaded capsule whose record is a confirmed PACKED one (settled, so
-- never one still settling, left uncertain by a crash, unpacked or void). rec: a snapshot, a Store.status entry or
-- a Query reply. Nothing can be put into a capsule either way (MaxItemSize in the item script).
function Rules.cargoOpen(rec)
    return Rules.sandbox().AllowCargoTakeOut == true and rec ~= nil and rec.state == "PACKED" and rec.settled == true
end

-- Admin on either side: the server asks the connection (M.isAdmin, SP host = admin); an MP client reads its own role.
function Rules.isAdmin(player)
    if not isClient() then return M.isAdmin(player) end
    local role = player and player:getRole()
    return role ~= nil and Capability ~= nil and role:hasCapability(Capability.ManipulateVehicle) == true
end

function Rules.occupied(vehicle)
    for seat = 0, vehicle:getMaxPassengers() - 1 do
        if vehicle:getCharacter(seat) then return true end
    end
    return false
end

-- Why this vehicle cannot be packed by anyone right now, or nil (Pack.whyNot). Player rules are in packWhyNot.
function Rules.vehicleWhyNot(player, vehicle)
    if not vehicle or not vehicle:getSquare() then return "NO_VEHICLE" end
    local dx, dy = player:getX() - vehicle:getX(), player:getY() - vehicle:getY()
    if dx * dx + dy * dy > M.PACK_RANGE * M.PACK_RANGE then return "TOO_FAR" end
    if Rules.occupied(vehicle) then return "OCCUPIED" end
    if vehicle:getVehicleTowing() or vehicle:getVehicleTowedBy() then return "TOWING" end
    local animals = vehicle:getAnimals()
    if animals and animals:size() > 0 then return "ANIMALS" end
    if vehicle:isEngineRunning() then return "ENGINE_RUNNING" end
    for i = 0, vehicle:getPartCount() - 1 do
        local inv = vehicle:getPartByIndex(i):getItemContainer()
        if inv then
            for _, t in ipairs(M.TYPES) do
                if inv:containsTypeRecurse(t.loaded) then return "CAPSULE_INSIDE" end
            end
        end
    end
    return nil
end

-- Who may pack: a vehicle claimed in VehicleManager needs its Tow permission (the owner, players the owner or the
-- faction shared Tow with, or an admin with its override on): packing takes the vehicle away like towing does, and
-- Tow is never part of a share with everyone. Any other vehicle: admins always, others by SandboxVars PackPermission
-- (1 key in the inventory or in the ignition, 2 anyone, 3 admins only).
-- Returns ok, mode, why. mode: "VM" (VehicleManager's owner, or its refusal), "SHARED" (Tow shared with this
-- player), "KEY"/"ANY"/"ADMIN" (an admin passing in mode 1 or by VM override reports "ADMIN"); why: VM's reason code.
function Rules.mayPack(player, vehicle)
    local vm = MinidoracatVehicleManagerAPI
    if vm and vm.canUse then
        local ok, why = vm.canUse(player, vehicle, "TOW")
        -- An unclaimed vehicle has no owner there (VM allows anyone): the sandbox rule below decides instead
        if why ~= "UNCLAIMED" then
            if ok ~= true then return false, "VM", why end
            if why == "ADMIN" then return true, "ADMIN", why end
            return true, why == "OWNER" and "VM" or "SHARED", why
        end
    end
    local mode = tonumber(Rules.sandbox().PackPermission) or 1
    if mode == 2 then return true, "ANY" end
    if Rules.isAdmin(player) then return true, "ADMIN" end
    if mode == 3 then return false, "ADMIN" end
    local key = vehicle:isKeysInIgnition() or vehicle:getCurrentKey() ~= nil
        or player:getInventory():haveThisKeyId(vehicle:getKeyId()) ~= nil
    return key, "KEY"
end

-- Sandbox Type<id>: whether players may pack with this type. Off only stops packing; loaded capsules of the type are
-- still thrown and pressed, so no vehicle is ever shut in a capsule (design vcap-types-1012).
function Rules.typeOn(t)
    return t ~= nil and Rules.sandbox()["Type" .. t.id] ~= false
end

-- The player's first empty capsule of type t (any depth in the inventory), or nil.
function Rules.emptyCapsule(player, t)
    return t and player:getInventory():getFirstTypeRecurse(t.empty)
end

-- Every type the player has empty capsules of, in M.TYPES order: { { type, n, on }, ... } (the pack menu).
function Rules.emptyTypes(player)
    local inv, out = player:getInventory(), {}
    for _, t in ipairs(M.TYPES) do
        local n = inv:getCountTypeRecurse(t.empty)
        if n > 0 then out[#out + 1] = { type = t, n = n, on = Rules.typeOn(t) } end
    end
    return out
end

local function countIn(inv)
    local items, n = inv:getItems(), 0
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        n = n + 1
        if instanceof(it, "InventoryContainer") then n = n + countIn(it:getInventory()) end
    end
    return n
end

-- Items (any depth) that would go into the capsule with the vehicle.
function Rules.cargoCount(vehicle)
    local n = 0
    for i = 0, vehicle:getPartCount() - 1 do
        local inv = vehicle:getPartByIndex(i):getItemContainer()
        if inv then n = n + countIn(inv) end
    end
    return n
end

-- Everything the server checks before a player's pack with a capsule of type t, or nil.
function Rules.packWhyNot(player, vehicle, t)
    local why = Rules.vehicleWhyNot(player, vehicle)
    if why then return why end
    if not Rules.mayPack(player, vehicle) then return "NOT_ALLOWED" end
    if not Rules.emptyCapsule(player, t) then return "NO_CAPSULE" end
    if not Rules.typeOn(t) then return "TYPE_OFF" end
    return nil
end

return Rules
