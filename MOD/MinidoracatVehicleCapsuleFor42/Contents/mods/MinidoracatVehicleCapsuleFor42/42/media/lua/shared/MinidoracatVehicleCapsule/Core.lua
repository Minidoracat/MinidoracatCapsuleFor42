-- Vehicle Capsule: shared constants and helpers.
MinidoracatVehicleCapsule = MinidoracatVehicleCapsule or {}
local M = MinidoracatVehicleCapsule

M.MOD_ID = "MinidoracatVehicleCapsuleFor42"
M.MODULE = "MinidoracatVehicleCapsule" -- client command module and item module
M.LOG_PREFIX = "[MinidoracatVehicleCapsuleFor42] "
M.ITEM_EMPTY = "MinidoracatVehicleCapsule.Capsule"
M.ITEM_LOADED = "MinidoracatVehicleCapsule.LoadedCapsule"
M.PACK_RANGE = 8 -- tiles between player and vehicle (pack) or player and capsule on the ground (unpack)

function M.log(msg)
    print(M.LOG_PREFIX .. tostring(msg))
end

-- True for a loaded capsule's own inventory and for any container nested inside one (a bag in the cargo).
function M.isCapsuleContainer(container)
    local holder = container and container:getContainingItem()
    if not holder then return false end
    return holder:getFullType() == M.ITEM_LOADED or M.isCapsuleContainer(holder:getContainer())
end

-- True for cargo: an item anywhere inside a loaded capsule. The capsule itself is not inside one.
function M.inCapsule(item)
    return item ~= nil and M.isCapsuleContainer(item:getContainer())
end

-- Drops capsule containers from a java ArrayList<ItemContainer> in place (crafting and building input lists).
function M.withoutCapsules(list)
    if not list then return list end
    for i = list:size() - 1, 0, -1 do
        local c = list:get(i)
        if M.isCapsuleContainer(c) then list:remove(c) end
    end
    return list
end

-- Same rule as VehicleManager O.isAdmin: Capability.ManipulateVehicle on a dedicated server; SP host is admin.
function M.isAdmin(player)
    if player == nil then return false end
    if not isServer() then return not isClient() end
    if Capability == nil then return false end
    return checkPermissions(player, Capability.ManipulateVehicle) == true
end

return M
