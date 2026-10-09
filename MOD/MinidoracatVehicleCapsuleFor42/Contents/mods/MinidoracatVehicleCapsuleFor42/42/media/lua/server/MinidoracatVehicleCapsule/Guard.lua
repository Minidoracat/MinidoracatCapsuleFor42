-- Vehicle Capsule: server guards over loaded capsules, driven by one OnTickEvenPaused handler.
--   * Store.settleDue every tick. OnTick stops on an empty dedicated server with PauseEmpty; OnTickEvenPaused fires
--     at the top of IngameState.updateInternal, before the pause check (IngameState.java:1347 vs 1517-1520).
--   * Every PASS_MS, for loaded capsules in online players' inventories (any depth) and on the ground around them:
--     a stale record (UNPACKED and settled, or VOID) means the cargo is a second copy -> replace with an empty capsule;
--     otherwise sealed cargo that left the capsule is put back when the player carries it (cargo lock). Vanilla item
--     transfers are pure Java (ItemTransactionPacket -> TransactionManager.isConsistent/Transaction.update, no Lua
--     hook on the source), so the server can only undo them, not refuse them.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Store"
local M = MinidoracatVehicleCapsule
local Store = M.Store
local Guard = {}
M.Guard = Guard

Guard.PASS_MS = 1000
Guard.GROUND_RANGE = 2 -- squares around each player searched for capsules on the ground

-- "full.Type*n,..." of everything inside inv (any depth), for logs and history.
local function listing(inv)
    local counts = {}
    local function walk(c)
        local items = c:getItems()
        for i = 0, items:size() - 1 do
            local it = items:get(i)
            counts[it:getFullType()] = (counts[it:getFullType()] or 0) + 1
            if instanceof(it, "InventoryContainer") then walk(it:getInventory()) end
        end
    end
    walk(inv)
    local parts = {}
    for ft, n in pairs(counts) do parts[#parts + 1] = ft .. "*" .. n end
    return #parts > 0 and table.concat(parts, ",") or "-"
end
Guard.listing = listing

-- Puts an empty capsule where `capsule` is (same container, or the same square) and deletes it with its cargo.
local function replaceWithEmpty(player, capsule)
    local empty = instanceItem(M.ITEM_EMPTY)
    local wo = capsule:getWorldItem()
    if wo and wo:getSquare() then
        local sq = wo:getSquare()
        sq:transmitRemoveItemFromSquare(wo)
        capsule:setWorldItem(nil)
        if empty then sq:AddWorldInventoryItem(empty, 0.5, 0.5, 0) end
        return
    end
    local c = capsule:getContainer()
    if not c then return end
    if player then player:removeFromHands(capsule) end
    c:DoRemoveItem(capsule)
    sendRemoveItemFromContainer(c, capsule)
    if empty then
        c:AddItem(empty)
        sendAddItemToContainer(c, empty)
    end
end

-- The capsule's cargo is a second copy (Store.isStale): swap the capsule for an empty one and record what went.
function Guard.clear(player, capsule, capsuleId, snap, why)
    local items = listing(capsule:getInventory())
    replaceWithEmpty(player, capsule)
    Store.event(capsuleId, snap, "CLEARED", player, { why = why, items = items })
end

local function idsIn(inv, set)
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        set[it:getID()] = true
        if instanceof(it, "InventoryContainer") then idsIn(it:getInventory(), set) end
    end
    return set
end

local reported = {} -- "capsuleId:itemId" -> true: cargo that left and could not be put back, logged once per run

-- Puts sealed cargo the player took out back into the capsule (top level). Equipped, worn or attached items and
-- items the player does not carry are only logged.
local function lock(player, capsule, capsuleId, sealed)
    if not sealed or #sealed == 0 then return end
    local here = idsIn(capsule:getInventory(), {})
    local inv, box = player:getInventory(), capsule:getInventory()
    local back, gone = {}, {}
    for _, itemId in ipairs(sealed) do
        if not here[itemId] then
            local item = inv:getItemWithIDRecursiv(itemId)
            if item and M.inCapsule(item) then
                -- already back: it came inside a bag that was put back above (sealed lists bags before contents)
            elseif item and not (player:isEquipped(item) or player:isAttachedItem(item)) then
                local from = item:getContainer()
                from:Remove(item)
                sendRemoveItemFromContainer(from, item)
                box:AddItem(item)
                sendAddItemToContainer(box, item)
                back[#back + 1] = item:getFullType() .. "#" .. itemId
                idsIn(box, here)
            elseif not reported[capsuleId .. ":" .. itemId] then
                reported[capsuleId .. ":" .. itemId] = true
                gone[#gone + 1] = (item and (item:getFullType() .. "#equipped#") or "#") .. itemId
            end
        end
    end
    if #back == 0 and #gone == 0 then return end
    local snap = Store.read(capsuleId)
    if not snap then return end
    if #back > 0 then Store.event(capsuleId, snap, "CARGO_LOCK", player, { why = "returned", items = table.concat(back, ",") }) end
    if #gone > 0 then Store.event(capsuleId, snap, "CARGO_LOCK", player, { why = "missing", items = table.concat(gone, ",") }) end
end

-- One loaded capsule seen by a pass: clear it when stale, otherwise keep its cargo inside.
function Guard.check(player, capsule)
    local capsuleId = capsule:getID()
    local st = Store.status(capsuleId)
    if not st then return end
    if Store.isStale(st) then
        local snap = Store.read(capsuleId)
        if snap and Store.isStale(snap) then Guard.clear(player, capsule, capsuleId, snap, "scan") end
        return
    end
    lock(player, capsule, capsuleId, st.sealed)
end

local function groundCapsules(player, out)
    local cell, r = getCell(), Guard.GROUND_RANGE
    local px, py, pz = math.floor(player:getX()), math.floor(player:getY()), math.floor(player:getZ())
    for dx = -r, r do
        for dy = -r, r do
            local sq = cell:getGridSquare(px + dx, py + dy, pz)
            local objs = sq and sq:getWorldObjects()
            for i = 0, (objs and objs:size() or 0) - 1 do
                local it = objs:get(i):getItem()
                if it and it:getFullType() == M.ITEM_LOADED then out[#out + 1] = it end
            end
        end
    end
    return out
end

function Guard.pass(player)
    local found = player:getInventory():getAllTypeRecurse(M.ITEM_LOADED)
    local list = {}
    for i = 0, found:size() - 1 do list[#list + 1] = found:get(i) end
    groundCapsules(player, list)
    for _, capsule in ipairs(list) do Guard.check(player, capsule) end
end

local function players()
    local out = {}
    if isServer() then
        local online = getOnlinePlayers()
        for i = 0, (online and online:size() or 0) - 1 do out[#out + 1] = online:get(i) end
    else
        for i = 0, getNumActivePlayers() - 1 do
            local p = getSpecificPlayer(i)
            if p then out[#out + 1] = p end
        end
    end
    return out
end

local nextPass = 0
function Guard.tick()
    local now = getTimestampMs()
    Store.settleDue(now)
    if now < nextPass then return end
    nextPass = now + Guard.PASS_MS
    for _, p in ipairs(players()) do
        local ok, err = pcall(Guard.pass, p)
        if not ok then M.log("guard pass failed: " .. tostring(err)) end
    end
end
Events.OnTickEvenPaused.Add(Guard.tick)

return Guard
