-- Vehicle Capsule: keep loaded capsules out of Minidoracat Economy (market, auctions, buy requests, shop buyback).
-- Economy stores a traded item as a snapshot and rebuilds it with instanceItem, so it comes back with a new item ID;
-- a capsule's record is keyed by that ID, so a rebuilt capsule loses its vehicle ("record not on this server").
-- Economy API rev 5 refuses a blocked type in every trading channel. Older Economy: the loaded capsule's display
-- category (Container) is outside Economy's default and production whitelists, which only an admin can change.
-- OnInitGlobalModData runs once every server file has loaded, on a dedicated server and in single player alike.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule

local function block()
    local api = MinidoracatEconomy and MinidoracatEconomy.v1
    if not api then return end
    local caps = api.CAPABILITIES
    if not (api.API_MAJOR == 1 and (api.API_REVISION or 0) >= 5 and type(caps) == "table"
        and caps.blockItemType == true and type(api.blockItemType) == "function") then
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
Events.OnInitGlobalModData.Add(block)
