-- Vehicle Capsule: player rules shared by the client menus (what the tooltip rows show) and the server actions
-- (what complete() enforces). The client copy only decides the menu; the server checks again before anything moves.
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule
local Rules = {}
M.Rules = Rules

Rules.PACK_SECONDS = 10
Rules.THROW_RANGE = 8 -- tiles from the thrower to the landing point
Rules.PRESS_RANGE = 3 -- tiles from a capsule on the ground to the landing point
Rules.NAME_MAX = 64

function Rules.sandbox()
    return SandboxVars and SandboxVars.MinidoracatVehicleCapsule or {}
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
        if inv and inv:containsTypeRecurse(M.ITEM_LOADED) then return "CAPSULE_INSIDE" end
    end
    return nil
end

-- Who may pack: a vehicle claimed in VehicleManager follows its MANAGE (the owner, or an admin with its override on);
-- any other vehicle: admins always, others by SandboxVars PackPermission (1 key in the inventory or in the ignition,
-- 2 anyone, 3 admins only).
-- Returns ok, mode ("VM"/"KEY"/"ANY"/"ADMIN"; an admin passing in mode 1 or by VM override reports "ADMIN").
function Rules.mayPack(player, vehicle)
    local vm = MinidoracatVehicleManagerAPI
    if vm and vm.canUse then
        local ok, why = vm.canUse(player, vehicle, "MANAGE")
        -- An unclaimed vehicle has no owner there (VM allows anyone): the sandbox rule below decides instead
        if why ~= "UNCLAIMED" then return ok == true, why == "ADMIN" and "ADMIN" or "VM" end
    end
    local mode = tonumber(Rules.sandbox().PackPermission) or 1
    if mode == 2 then return true, "ANY" end
    if Rules.isAdmin(player) then return true, "ADMIN" end
    if mode == 3 then return false, "ADMIN" end
    local key = vehicle:isKeysInIgnition() or vehicle:getCurrentKey() ~= nil
        or player:getInventory():haveThisKeyId(vehicle:getKeyId()) ~= nil
    return key, "KEY"
end

function Rules.emptyCapsule(player)
    return player:getInventory():getFirstTypeRecurse(M.ITEM_EMPTY)
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

-- Everything the server checks before a player's pack, or nil.
function Rules.packWhyNot(player, vehicle)
    local why = Rules.vehicleWhyNot(player, vehicle)
    if why then return why end
    if not Rules.mayPack(player, vehicle) then return "NOT_ALLOWED" end
    if not Rules.emptyCapsule(player) then return "NO_CAPSULE" end
    return nil
end

-- The capsule name a client composed in its own language: no control characters, no [ ] (item name markup) and
-- no < > (rich-text tags in tooltips), trimmed, at most NAME_MAX UTF-16 units. nil when nothing usable is left.
function Rules.cleanName(name)
    if type(name) ~= "string" then return nil end
    name = string.gsub(name, "[%c%[%]<>]", "")
    name = string.match(name, "^%s*(.-)%s*$")
    if #name > Rules.NAME_MAX then name = string.sub(name, 1, Rules.NAME_MAX) end
    if name == "" then return nil end
    return name
end

return Rules
