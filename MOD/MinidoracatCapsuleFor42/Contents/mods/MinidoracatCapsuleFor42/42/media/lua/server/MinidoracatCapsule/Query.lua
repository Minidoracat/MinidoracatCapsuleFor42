-- Universal Capsule: capsule summaries for the tooltip and the 3D preview (server authority).
-- The capsule item only carries its id; the vehicle, its condition and the cargo list come from its record (Store).
-- Replies are raw data (script, parts, manifest, history times): the client words them in the player's language.
-- A regular player may only ask about capsules on them or within LOOK_RANGE (ground, containers, vehicle parts);
-- admins (Capability.ManipulateVehicle) about any. When a record is written every client drops its cached copy.
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Animal"
require "MinidoracatCapsule/Store"
local M = MinidoracatCapsule
local Store = M.Store
local Query = {}
M.Query = Query

Query.MAX_IDS = 20       -- ids per request
Query.LOOK_RANGE = 3     -- squares around the player (the loot window shows containers within ~1-2)
Query.MIN_GAP_MS = 100   -- per player; faster requests are dropped (the client retries what it still needs)

local function inContainer(c, capsuleId)
    return c ~= nil and c:getItemWithIDRecursiv(capsuleId) ~= nil
end

-- Where the capsule is when it is on the player or near enough to hover in the loot window, as a sighting for
-- Store.seen: { where = "player" | "ground" | "container" | "vehicle", by, x, y, z }; nil when it is not.
function Query.near(player, capsuleId)
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    if inContainer(player:getInventory(), capsuleId) then
        return { where = "player", by = player:getUsername(), x = px, y = py, z = pz }
    end
    local cell, r = getCell(), Query.LOOK_RANGE
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            if sq then
                local at = { x = px + dx, y = py + dy, z = pz }
                local wobs = sq:getWorldObjects()
                for i = 0, wobs:size() - 1 do
                    local it = wobs:get(i):getItem()
                    if it and it:getID() == capsuleId then at.where = "ground"; return at end
                    if it and instanceof(it, "InventoryContainer") and inContainer(it:getInventory(), capsuleId) then
                        at.where = "container"
                        return at
                    end
                end
                local objs = sq:getObjects()
                for i = 0, objs:size() - 1 do
                    local o = objs:get(i)
                    for k = 0, o:getContainerCount() - 1 do
                        if inContainer(o:getContainerByIndex(k), capsuleId) then at.where = "container"; return at end
                    end
                end
                local v = sq:getVehicleContainer()
                if v then
                    for k = 0, v:getPartCount() - 1 do
                        if inContainer(v:getPartByIndex(k):getItemContainer(), capsuleId) then at.where = "vehicle"; return at end
                    end
                end
            end
        end
    end
    return nil
end

-- Compact snapshot for display. parts: { id, c = condition, i = item, ic = item condition, u = uses, a = amount }.
-- An animal record (kind "animal") carries `animal` (Animal.view) instead of the vehicle fields; pregnancy and
-- fertilization only when `breeding` (the asking player's Husbandry is above 2, the vanilla rule).
function Query.summary(capsuleId, snap, breeding)
    local h = snap.history or {}
    local first, last = h[1] or {}, h[#h] or {}
    local out = {
        ok = true, id = capsuleId, state = snap.state, settled = snap.settled == true,
        uncertain = Store.uncertain(capsuleId, snap), by = snap.packedBy,
        t = first.t, last = { ev = last.ev, t = last.t, by = last.by },
    }
    if snap.kind == "animal" then
        out.kind, out.animal = "animal", M.Animal.view(snap.animal, breeding)
        return out
    end
    local parts = {}
    for id, ps in pairs(snap.parts or {}) do
        parts[#parts + 1] = { id = id, c = ps.cond, i = ps.item, ic = ps.icond, u = ps.uses, a = ps.amount }
    end
    local manifest = {}
    for ft, n in pairs(snap.manifest or {}) do manifest[#manifest + 1] = { ft = ft, n = n } end
    out.script, out.name, out.skin, out.parts, out.manifest = snap.script, snap.name, snap.skin, parts, manifest
    return out
end

-- Vanilla shows (and sends) an animal's pregnancy only to Husbandry > 2 (NetworkPlayerAI.java:212-222).
local function breeding(player)
    return Perks ~= nil and player:getPerkLevel(Perks.Husbandry) > 2
end

-- Answers each id: summary, or { ok = false, id, why = "FAR" | "NO_SNAPSHOT" | "CORRUPT" }. A capsule near the
-- player is a sighting (Store.seen), also when an admin asks.
function Query.query(player, ids)
    local admin = M.isAdmin(player)
    local out = {}
    if type(ids) ~= "table" then return { items = out } end
    for i = 1, math.min(#ids, Query.MAX_IDS) do
        local id = tonumber(ids[i])
        if id then
            local at = Query.near(player, id)
            if not admin and not at then
                out[#out + 1] = { ok = false, id = id, why = "FAR" }
            else
                local snap, why = Store.read(id)
                out[#out + 1] = snap and Query.summary(id, snap, breeding(player)) or { ok = false, id = id, why = why }
                if snap and at then Store.seen(id, at) end
            end
        end
    end
    return { items = out }
end

local lastAsk = {} -- username -> ms
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= M.MODULE or command ~= "query" or not player then return end
    local name, now = player:getUsername(), getTimestampMs()
    local prev = lastAsk[name]
    if prev and now >= prev and now - prev < Query.MIN_GAP_MS then return end
    lastAsk[name] = now
    local ok, res = pcall(Query.query, player, type(args) == "table" and args.ids or nil)
    if not ok then
        M.log("query failed: " .. tostring(res))
        return
    end
    sendServerCommand(player, M.MODULE, "query", res)
end)

-- A written record changed what clients may have cached (state, settled). Quiet writes (a sighting) change nothing
-- they show. SP has no clients to tell: the client cache there is cleared by the same listener through
-- M.QueryChanged (client Info.lua).
Store.listeners[#Store.listeners + 1] = function(capsuleId, _, written, quiet)
    if not written or quiet then return end
    if isServer() then
        sendServerCommand(M.MODULE, "queryChanged", { id = capsuleId })
    elseif M.QueryChanged then
        M.QueryChanged(capsuleId)
    end
end

return Query
