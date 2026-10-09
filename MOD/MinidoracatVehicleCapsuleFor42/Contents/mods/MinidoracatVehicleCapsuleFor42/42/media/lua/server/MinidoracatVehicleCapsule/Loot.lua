-- Vehicle Capsule: empty capsules in four vanilla loot locations (server / SP; MP clients do not fill containers).
-- Switches and weights are sandbox options (page MinidoracatVehicleCapsuleLoot); the weight goes into
-- ProceduralDistributions as is. How a change takes effect, same as MiniMapWatch Loot.lua:
--   * game start: OnPostDistributionMerge edits the list before ItemPickerJava.Parse (IsoWorld.java:1886-1901);
--     an SP save's sandbox loads after that (IsoWorld.java:1894-1896), the first poll catches up.
--   * sandbox change: the vanilla page only re-parses on the side that applied it, and a dedicated server never
--     re-parses on a received sandbox (GameServer.java:1710-1726). So every POLL_MS the native options are compared
--     with what was applied; on a difference our entries are rebuilt and IsoWorld.parseDistributions() runs.
-- Native options first: the SP sandbox UI only sets native options, SandboxVars lag (SandboxOptions.java:572-582).
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule
local Loot = {}
M.Loot = Loot

Loot.POLL_MS = 1000
Loot.ITEM = M.ITEM_EMPTY
-- { switch option, weight option, default switch, default weight, loot tables }
Loot.PLACES = {
    { "LootMechanic", "LootMechanicWeight", true, 0.5, { "MechanicShelfTools", "CrateMechanics" } },
    { "LootCarSupply", "LootCarSupplyWeight", true, 0.5, { "CarSupplyTools" } },
    { "LootGasStation", "LootGasStationWeight", true, 0.3, { "GasStorageMechanics" } },
    { "LootGarage", "LootGarageWeight", false, 0.2, { "GarageMechanics" } },
}

-- Native sandbox value, falling back to SandboxVars, then to `default`.
function Loot.option(key, default)
    local opts = getSandboxOptions and getSandboxOptions()
    local o = opts and opts:getOptionByName("MinidoracatVehicleCapsule." .. key)
    if o then return o:getValue() end
    local sv = SandboxVars and SandboxVars.MinidoracatVehicleCapsule
    if sv and sv[key] ~= nil then return sv[key] end
    return default
end

-- What should be in the tables right now: { [table] = weight }. Weight 0 or a switch off means no entry.
function Loot.wanted()
    local out = {}
    if Loot.option("LootEnabled", true) == false then return out end
    for _, p in ipairs(Loot.PLACES) do
        local w = tonumber(Loot.option(p[2], p[4])) or p[4]
        if Loot.option(p[1], p[3]) ~= false and w > 0 then
            for _, t in ipairs(p[5]) do out[t] = (out[t] or 0) + w end
        end
    end
    return out
end

-- Compared as a string: switches and weights in a fixed order.
function Loot.signature(wanted)
    local parts = {}
    for _, p in ipairs(Loot.PLACES) do
        for _, t in ipairs(p[5]) do parts[#parts + 1] = t .. "=" .. tostring(wanted[t] or 0) end
    end
    return table.concat(parts, ";")
end

-- Removes our pairs from every table we touch, then adds the wanted ones, in place (other mods hold the same
-- tables). Returns the number of entries added.
local missingLogged = {}
function Loot.apply(list, wanted)
    local added = 0
    for _, p in ipairs(Loot.PLACES) do
        for _, name in ipairs(p[5]) do
            local items = list[name] and list[name].items
            if type(items) == "table" then
                local j, n = 1, #items
                for i = 1, n, 2 do
                    if items[i] ~= Loot.ITEM then
                        items[j], items[j + 1] = items[i], items[i + 1]
                        j = j + 2
                    end
                end
                for k = n, j, -1 do items[k] = nil end
                if wanted[name] and wanted[name] > 0 then
                    items[#items + 1] = Loot.ITEM
                    items[#items + 1] = wanted[name]
                    added = added + 1
                end
            elseif not missingLogged[name] then
                missingLogged[name] = true
                M.log("loot table " .. name .. " not found in ProceduralDistributions; skipped")
            end
        end
    end
    return added
end

Loot.applied = nil
-- parse: let Java re-read the tables (after the merge event the engine parses them by itself).
function Loot.sync(parse)
    local list = ProceduralDistributions and ProceduralDistributions.list
    if type(list) ~= "table" then return end
    local wanted = Loot.wanted()
    local sig = Loot.signature(wanted)
    if sig == Loot.applied then return end
    local added = Loot.apply(list, wanted)
    Loot.applied, Loot.syncedAt = sig, getTimestampMs()
    if parse then IsoWorld.parseDistributions() end -- ItemPickerJava.Parse + InitSandboxLootSettings (IsoWorld.java:3326-3329)
    M.log("loot tables " .. (parse and "updated after a sandbox change" or "prepared") .. " (" .. added
        .. " entries: " .. sig .. ")")
end

Events.OnPostDistributionMerge.Add(function() Loot.sync(false) end)

local lastPoll = nil
Events.OnTickEvenPaused.Add(function()
    if Loot.applied == nil then return end -- not merged yet (main menu, loading)
    local now = getTimestampMs()
    if lastPoll and now >= lastPoll and now - lastPoll < Loot.POLL_MS then return end
    lastPoll = now
    Loot.sync(true)
end)

return Loot
