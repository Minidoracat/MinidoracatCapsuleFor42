-- Vehicle Capsule: loaded capsules in Minidoracat Economy. API rev 6 (unique item types): market listings and auctions
-- take them, cargo included (Trade.lua carries the record and the cargo across Economy's rebuild); buy orders and the
-- shop do not (Economy refuses unique types there). Without rev 6, or when the registration is refused, they stay out
-- of every channel: a capsule Economy rebuilt would come back with a new item id, away from its record. Rev 5
-- blockItemType refuses them; older Economy leaves them out while its whitelist leaves the loaded capsule's display
-- category (Container) out, as the default and production whitelists do.
-- OnInitGlobalModData runs once every server file has loaded, on a dedicated server and in single player alike.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Trade"
local M = MinidoracatVehicleCapsule

local function block(api)
    if not ((api.API_REVISION or 0) >= 5 and api.CAPABILITIES.blockItemType == true
        and type(api.blockItemType) == "function") then
        M.log("Minidoracat Economy API rev " .. tostring(api.API_REVISION) .. " cannot block item types; loaded capsules"
            .. " stay off its market only while its whitelist leaves the Container category out")
        return
    end
    local ok, res, why = pcall(api.blockItemType, M.ITEM_LOADED, M.MOD_ID)
    if ok and res == true then
        M.log("loaded capsules blocked from Minidoracat Economy trading")
    else
        M.log("Minidoracat Economy refused to block loaded capsules: " .. tostring(ok and why or res))
    end
end

local function hook()
    local api = MinidoracatEconomy and MinidoracatEconomy.v1
    if not (api and api.API_MAJOR == 1 and type(api.CAPABILITIES) == "table") then return end
    if (api.API_REVISION or 0) >= 6 and api.CAPABILITIES.uniqueItemTypes == true
        and type(api.registerUniqueItemType) == "function" then
        local ok, res, why = pcall(api.registerUniqueItemType, M.ITEM_LOADED, M.MOD_ID, M.Trade.handler)
        if ok and res == true then
            M.log("loaded capsules tradeable through Minidoracat Economy (market listings, auctions; cargo included)")
            return
        end
        M.log("Minidoracat Economy refused loaded capsules as a unique item type: " .. tostring(ok and why or res))
    end
    block(api)
end
Events.OnInitGlobalModData.Add(hook)
