-- Universal Capsule: what players do (pack, throw, press), server side. SP runs the same functions locally.
-- MP timed actions run complete() on the server only, rebuilt from the new() arguments the client sent
-- (NetTimedAction.java:142-170), so `character` can name anyone. Identity comes from OnClientCommand (the server
-- maps the connection to the player): the client sends an intent when it queues the action, and complete() only
-- goes ahead when that same player sent a matching intent (same scheme as VehicleManager's prepareAction).
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Footprint"
require "MinidoracatCapsule/Store"
require "MinidoracatCapsule/Pack"
require "MinidoracatCapsule/Unpack"
require "MinidoracatCapsule/Throw"
require "MinidoracatCapsule/Fx"
local M = MinidoracatCapsule
local Rules, Footprint, Store, Throw, Fx = M.Rules, M.Footprint, M.Store, M.Throw, M.Fx
local Play = { intents = {} }
M.Play = Play

local INTENT_TTL_MS = 60000 -- queue (walk there) + action time
local INTENTS_PER_PLAYER = 8
local KINDS = { pack = true, packAnimal = true, throw = true, press = true }

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

-- args: kind ("pack" / "packAnimal" / "throw" / "press"), id (vehicle id for pack, the animal's online id for
-- packAnimal, capsule id otherwise), type (packing only: the id of the capsule type to pack with, M.TYPES; Play.pack /
-- Play.packAnimal check the player carries one and that it is enabled).
function Handlers.intent(player, args)
    local id = tonumber(args.id)
    if not (KINDS[args.kind] and id) then return end
    local list = liveIntents(player) or {}
    Play.intents[player:getUsername()] = list
    if #list >= INTENTS_PER_PLAYER then table.remove(list, 1) end
    list[#list + 1] = { kind = args.kind, id = id, type = M.TYPE_BY_ID[tostring(args.type)], exp = now() + INTENT_TTL_MS }
end

-- The vehicle script (or for an animal record kind "animal" and the animal's names) of a capsule the player holds or
-- stands near: the landing cursor needs the vehicle's size, an animal takes one square.
function Play.capsuleInfo(player, capsuleId)
    local capsule = capsuleId and M.Unpack.findCapsule(player, capsuleId)
    local snap = capsule and Store.read(capsuleId)
    local a = snap and snap.kind == "animal" and type(snap.animal) == "table" and snap.animal or nil
    Play.send(player, "capsuleInfo", { capsuleId = capsuleId, ok = snap ~= nil, script = snap and snap.script,
        state = snap and snap.state, kind = snap and snap.kind,
        animal = a and { type = a.type, breed = a.breed, name = a.name } or nil })
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
-- ISPackVehicleAction. typeId: the SP client's choice (MP takes it from the intent).
function Play.pack(player, vehicle, typeId)
    local id = vehicle and vehicle:getId()
    local intent = Play.takeIntent(player, "pack", id)
    if not intent then return refuse(player, "pack", "NO_INTENT", id) end
    local t = intent.type or M.TYPE_BY_ID[tostring(typeId)]
    local why = Rules.packWhyNot(player, vehicle, t)
    local res = why and { ok = false, why = why, vehicleId = id, type = t and t.id } -- the client words NOT_ALLOWED
        or M.Pack.pack(player, vehicle, { type = t, empty = Rules.emptyCapsule(player, t) }) -- like its menu row
    if not res.ok then refuse(player, "pack", tostring(res.why), id) end
    Play.send(player, "packed", res)
    return res.ok == true
end

-- ISPackAnimalAction. The intent names the animal by its online id (what the client sees; the server rebuilt the
-- action's animal from it). typeId: the SP client's choice (MP takes it from the intent).
function Play.packAnimal(player, animal, typeId)
    local id = animal and animal:getOnlineID()
    local intent = Play.takeIntent(player, "packAnimal", id)
    if not intent then return refuse(player, "packAnimal", "NO_INTENT", id) end
    local t = intent.type or M.TYPE_BY_ID[tostring(typeId)]
    local why = Rules.packAnimalWhyNot(player, animal, t)
    local res = why and { ok = false, why = why, kind = "animal", type = t and t.id }
        or M.Pack.packAnimal(player, animal, { capsule = Rules.emptyCapsule(player, t), typeId = t.id })
    if not res.ok then
        res.kind = "animal"
        refuse(player, "packAnimal", tostring(res.why), id)
    end
    Play.send(player, "packed", res)
    return res.ok == true
end

-- The capsule leaves the hand: every client nearby sees it fly, drawn and heard as its own type.
local function fly(action)
    local player, t = action.character, M.typeOf(action.item)
    action.flightAt = now()
    Fx.broadcast("flight", { x0 = player:getX(), y0 = player:getY(), z0 = player:getZ(),
        x = action.x, y = action.y, z = action.z, style = t and t.index })
end

-- ISThrowCapsuleAction release (server / SP).
function Play.released(action)
    local item = action.item
    if not (item and Play.hasIntent(action.character, "throw", item:getID())) then return end
    fly(action)
end

-- ISThrowCapsuleAction complete: re-check the capsule and the spot, then land FLIGHT_MS after the release.
function Play.throw(action)
    local player, item, x, y, z = action.character, action.item, action.x, action.y, action.z
    local id = item and item:getID()
    if not (item and M.isLoaded(item) and player:getInventory():containsID(id)) then
        return refuse(player, "throw", "NO_CAPSULE", id)
    end
    if not Play.takeIntent(player, "throw", id) then return refuse(player, "throw", "NO_INTENT", id) end
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    local why = Footprint.reach(px, py, pz, x, y, z, Rules.THROW_RANGE + 1, true)
    if why then
        Play.send(player, "landed", { ok = false, why = why, capsuleId = id, mode = "throw" })
        return refuse(player, "throw", why, id)
    end
    -- No release event: the admin power "timed action instant" ends the action on its first tick, before the clip
    -- or the server's emulated events. The intent is already taken, so fly here (Play.released would refuse).
    if not action.flightAt then fly(action) end
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
    if not (sq and M.isLoaded(capsule)) then return refuse(player, "press", "NO_CAPSULE", capsuleId) end
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
