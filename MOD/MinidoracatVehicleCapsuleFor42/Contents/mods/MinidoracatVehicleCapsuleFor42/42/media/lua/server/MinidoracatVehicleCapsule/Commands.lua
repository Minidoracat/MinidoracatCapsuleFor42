-- Vehicle Capsule: admin-only debug entry points (Phase 1 E2E). The server re-resolves every target by id;
-- client coordinates are only accepted as the unpack spot, within PACK_RANGE of the player.
-- Real player actions/UI come in later phases.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Pack"
require "MinidoracatVehicleCapsule/Unpack"
local M = MinidoracatVehicleCapsule
local Commands = {}
M.Commands = Commands

-- SP has no server->client channel (sendServerCommand is a no-op there): SP callers call Pack/Unpack directly.
local function reply(player, cmd, args)
    if isServer() then sendServerCommand(player, M.MODULE, cmd, args) end
end

function Commands.debugPack(player, args)
    local id = tonumber(args.vehicleId)
    local vehicle = id and id >= 0 and getVehicleById(id)
    if not vehicle then return { ok = false, why = "NO_VEHICLE" } end
    return M.Pack.pack(player, vehicle)
end

function Commands.debugUnpack(player, args)
    local capsuleId = tonumber(args.capsuleId)
    local capsule = capsuleId and M.Unpack.findCapsule(player, capsuleId)
    if not capsule then return { ok = false, why = "NO_CAPSULE" } end
    local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
    if not (x and y) then return { ok = false, why = "BAD_ARGS" } end
    local dx, dy = player:getX() - x, player:getY() - y
    if math.sqrt(dx * dx + dy * dy) > M.PACK_RANGE + 4 then return { ok = false, why = "TOO_FAR" } end
    local square = getCell():getGridSquare(x, y, z)
    return M.Unpack.unpack(player, capsule, square, args.dir, {
        transmit = args.transmit == true or args.transmit == "1",
        persist = not (args.persist == false or args.persist == "0"),
    })
end

-- Read-only: snapshot state and history size (no modData dump).
function Commands.debugInfo(player, args)
    local snap, why = M.Store.read(tonumber(args.capsuleId) or -1)
    if not snap then return { ok = false, why = why } end
    return { ok = true, state = snap.state, script = snap.script, keyId = snap.keyId,
        history = snap.history and #snap.history or 0 }
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= M.MODULE then return end
    local fn = Commands[command]
    if not fn then return end
    if not M.isAdmin(player) then
        M.log("refused " .. tostring(command) .. " from non-admin " .. tostring(player and player:getUsername()))
        return
    end
    local ok, res = pcall(fn, player, args or {})
    if not ok or type(res) ~= "table" then
        M.log(command .. " failed: " .. tostring(res))
        res = { ok = false, why = "ERROR" }
    end
    M.log(command .. " by " .. player:getUsername() .. " -> ok=" .. tostring(res.ok) .. " why=" .. tostring(res.why))
    reply(player, command, res)
end)

return Commands
