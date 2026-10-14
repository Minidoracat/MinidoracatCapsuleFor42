-- Pack & Throw: loaded capsules in Minidoracat Economy, every type registered on its own (one full type each). API
-- rev 6 (unique item types): market listings and auctions take them, cargo included (Trade.lua carries the record and
-- the cargo across Economy's rebuild); buy orders and the shop do not (Economy refuses unique types there). Without
-- rev 6, or when a registration is refused, that type stays out of every channel: a capsule Economy rebuilt would come
-- back with a new item id, away from its record. Rev 5 blockItemType refuses them; older Economy leaves them out while
-- its whitelist leaves the loaded capsules' display category (Container) out, as the default and production
-- whitelists do. Empty capsules are ordinary items: admins list them in the shop (client/AdminPanel.lua "List...").
-- OnInitGlobalModData runs once every server file has loaded, on a dedicated server and in single player alike.
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Trade"
local M = MinidoracatCapsule

local function block(api, t)
    if not ((api.API_REVISION or 0) >= 5 and api.CAPABILITIES.blockItemType == true
        and type(api.blockItemType) == "function") then
        M.log("Minidoracat Economy API rev " .. tostring(api.API_REVISION) .. " cannot block item types; loaded capsules"
            .. " stay off its market only while its whitelist leaves the Container category out")
        return
    end
    local ok, res, why = pcall(api.blockItemType, t.loaded, M.MOD_ID)
    if ok and res == true then
        M.log("loaded capsules " .. t.id .. " blocked from Minidoracat Economy trading")
    else
        M.log("Minidoracat Economy refused to block loaded capsules " .. t.id .. ": " .. tostring(ok and why or res))
    end
end

local function hook()
    local api = MinidoracatEconomy and MinidoracatEconomy.v1
    if not (api and api.API_MAJOR == 1 and type(api.CAPABILITIES) == "table") then return end
    local unique = (api.API_REVISION or 0) >= 6 and api.CAPABILITIES.uniqueItemTypes == true
        and type(api.registerUniqueItemType) == "function"
    local n = 0
    for _, t in ipairs(M.TYPES) do
        local done = false
        if unique then
            local ok, res, why = pcall(api.registerUniqueItemType, t.loaded, M.MOD_ID, M.Trade.handler)
            done = ok and res == true
            if not done then
                M.log("Minidoracat Economy refused loaded capsules " .. t.id .. " as a unique item type: "
                    .. tostring(ok and why or res))
            end
        end
        if done then n = n + 1 else block(api, t) end
    end
    if n > 0 then
        M.log(n .. " loaded capsule types tradeable through Minidoracat Economy (market listings, auctions; cargo included)")
    end
end
Events.OnInitGlobalModData.Add(hook)
