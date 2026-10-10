-- Vehicle Capsule: what players do (pack, throw, press), server side. SP runs the same functions locally.
-- MP timed actions run complete() on the server only, rebuilt from the new() arguments the client sent
-- (NetTimedAction.java:142-170), so `character` can name anyone. Identity comes from OnClientCommand (the server
-- maps the connection to the player): the client sends an intent when it queues the action, and complete() only
-- goes ahead when that same player sent a matching intent (same scheme as VehicleManager's prepareAction).
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Rules"
require "MinidoracatVehicleCapsule/Footprint"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Pack"
require "MinidoracatVehicleCapsule/Unpack"
require "MinidoracatVehicleCapsule/Throw"
require "MinidoracatVehicleCapsule/Fx"
local M = MinidoracatVehicleCapsule
local Rules, Footprint, Store, Throw, Fx = M.Rules, M.Footprint, M.Store, M.Throw, M.Fx
local Play = { intents = {} }
M.Play = Play

local INTENT_TTL_MS = 60000 -- queue (walk there) + action time
local INTENTS_PER_PLAYER = 8
local KINDS = { pack = true, throw = true, press = true }

-- Server -> one client. SP has no channel (sendServerCommand is a no-op there): hand it to the client code directly.
function Play.send(player, cmd, args)
    if isServer() then
        sendServerCommand(player, M.MODULE, cmd, args)
    elseif M.onServerCommand then
        M.onServerCommand(cmd, args)
    end
end

local function now() return getTimestampMs() end

local function liveIntents(player)
    local list = Play.intents[player:getUsername()]
    if not list then return nil end
    local t = now()
    for i = #list, 1, -1 do
        if list[i].exp < t then table.remove(list, i) end
    end
    return list
end

local function findIntent(player, kind, id)
    local list = liveIntents(player)
    for i, it in ipairs(list or {}) do
        if it.kind == kind and it.id == id then return it, i, list end
    end
    return nil
end

-- The matching intent (removed), or nil. SP has one local player and no forged actions: always passes.
function Play.takeIntent(player, kind, id)
    if not isServer() then return {} end
    local it, i, list = findIntent(player, kind, id)
    if it then table.remove(list, i) end
    return it
end

function Play.hasIntent(player, kind, id)
    return not isServer() or findIntent(player, kind, id) ~= nil
end

local function refuse(player, what, why, id)
    M.log(what .. " refused by=" .. tostring(player and player:getUsername()) .. " why=" .. why .. " id=" .. tostring(id))
    return false
end

-- ---------------------------------------------------------------- client commands
local Handlers = {}

-- args: kind ("pack" / "throw" / "press"), id (vehicle id for pack, capsule id otherwise), name (pack only).
function Handlers.intent(player, args)
    local id = tonumber(args.id)
    if not (KINDS[args.kind] and id) then return end
    local list = liveIntents(player) or {}
    Play.intents[player:getUsername()] = list
    if #list >= INTENTS_PER_PLAYER then table.remove(list, 1) end
    list[#list + 1] = { kind = args.kind, id = id, name = Rules.cleanName(args.name), exp = now() + INTENT_TTL_MS }
end

-- The vehicle script of a capsule the player holds or stands near (the landing cursor needs its size).
function Play.capsuleInfo(player, capsuleId)
    local capsule = capsuleId and M.Unpack.findCapsule(player, capsuleId)
    local snap = capsule and Store.read(capsuleId)
    Play.send(player, "capsuleInfo", { capsuleId = capsuleId, ok = snap ~= nil, script = snap and snap.script,
        state = snap and snap.state })
end

function Handlers.capsuleInfo(player, args)
    Play.capsuleInfo(player, tonumber(args.capsuleId))
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= M.MODULE or not player then return end
    local fn = Handlers[command]
    if fn then fn(player, args or {}) end
end)

-- ---------------------------------------------------------------- action results (complete() on the server)
-- ISPackVehicleAction. localName: the SP client's name (MP takes it from the intent).
function Play.pack(player, vehicle, localName)
    local id = vehicle and vehicle:getId()
    local intent = Play.takeIntent(player, "pack", id)
    if not intent then return refuse(player, "pack", "NO_INTENT", id) end
    local why = Rules.packWhyNot(player, vehicle)
    local res = why and { ok = false, why = why, vehicleId = id } -- the client words a NOT_ALLOWED like its menu row
        or M.Pack.pack(player, vehicle, { name = intent.name or Rules.cleanName(localName), empty = Rules.emptyCapsule(player) })
    if not res.ok then refuse(player, "pack", tostring(res.why), id) end
    Play.send(player, "packed", res)
    return res.ok == true
end

-- ISThrowCapsuleAction release (server / SP): the capsule leaves the hand, every client nearby sees it fly.
function Play.released(action)
    local player, item = action.character, action.item
    if not (item and Play.hasIntent(player, "throw", item:getID())) then return end
    action.flightAt = now()
    Fx.broadcast("flight", { x0 = player:getX(), y0 = player:getY(), z0 = player:getZ(),
        x = action.x, y = action.y, z = action.z })
end

-- ISThrowCapsuleAction complete: re-check the capsule and the spot, then land FLIGHT_MS after the release.
function Play.throw(action)
    local player, item, x, y, z = action.character, action.item, action.x, action.y, action.z
    local id = item and item:getID()
    if not (item and item:getFullType() == M.ITEM_LOADED and player:getInventory():containsID(id)) then
        return refuse(player, "throw", "NO_CAPSULE", id)
    end
    if not Play.takeIntent(player, "throw", id) then return refuse(player, "throw", "NO_INTENT", id) end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local why = Footprint.reach(px, py, pz, x, y, z, Rules.THROW_RANGE + 1, true)
    if why then
        Play.send(player, "landed", { ok = false, why = why, capsuleId = id, mode = "throw" })
        return refuse(player, "throw", why, id)
    end
    if not action.flightAt then -- no release event (instant actions)
        Play.released(action)
        action.flightAt = action.flightAt or now()
    end
    Throw.schedule({ player = player, capsuleId = id, x = x, y = y, z = z, mode = "throw",
        dir = Footprint.dirOf(x - px, y - py) }, action.flightAt + Throw.FLIGHT_MS)
    return true
end

-- ISPressCapsuleAction complete: a capsule on the ground near the player; the vehicle lands within PRESS_RANGE of it.
function Play.press(player, capsuleId, x, y, z)
    if not Play.takeIntent(player, "press", capsuleId) then return refuse(player, "press", "NO_INTENT", capsuleId) end
    local capsule = M.Unpack.findCapsule(player, capsuleId)
    local wo = capsule and capsule:getWorldItem()
    local sq = wo and wo:getSquare()
    if not (sq and capsule:getFullType() == M.ITEM_LOADED) then return refuse(player, "press", "NO_CAPSULE", capsuleId) end
    local cx, cy = sq:getX() + 0.5, sq:getY() + 0.5
    local why = Footprint.reach(cx, cy, sq:getZ(), x, y, z, Rules.PRESS_RANGE + 0.5, false)
    if why then
        Play.send(player, "landed", { ok = false, why = why, capsuleId = capsuleId, mode = "press" })
        return refuse(player, "press", why, capsuleId)
    end
    Throw.schedule({ player = player, capsuleId = capsuleId, x = x, y = y, z = z, mode = "press",
        dir = Footprint.dirOf(x - cx, y - cy) }, now())
    return true
end

return Play
