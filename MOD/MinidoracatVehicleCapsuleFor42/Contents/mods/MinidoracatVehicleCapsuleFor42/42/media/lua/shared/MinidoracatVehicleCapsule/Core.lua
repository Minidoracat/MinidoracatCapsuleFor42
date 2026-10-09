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

-- Same rule as VehicleManager O.isAdmin: Capability.ManipulateVehicle on a dedicated server; SP host is admin.
function M.isAdmin(player)
    if player == nil then return false end
    if not isServer() then return not isClient() end
    if Capability == nil then return false end
    return checkPermissions(player, Capability.ManipulateVehicle) == true
end

return M
