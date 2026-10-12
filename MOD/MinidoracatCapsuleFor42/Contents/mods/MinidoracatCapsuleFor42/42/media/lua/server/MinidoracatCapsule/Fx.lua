-- Universal Capsule: tell nearby clients to draw an effect (client/MinidoracatCapsule/Effects.lua). The server only
-- sends a few numbers; smoke, flash and sound are local to each client and attract nothing. The sandbox zombie radius
-- is the only world sound (addSound). SP has no server->client channel: Effects.play is called directly.
if isClient() then return end
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Rules"
local M = MinidoracatCapsule
local Fx = {}
M.Fx = Fx

Fx.RANGE = 30 -- tiles from the effect to a player who gets it
local nextId = 0

-- kind: "pack" | "unpack" (x, y, z) or "flight" (x0, y0, z0 -> x, y, z).
function Fx.broadcast(kind, args)
    nextId = nextId + 1
    args.kind, args.id = kind, nextId
    local radius = kind == "flight" and 0 or (tonumber(M.Rules.sandbox().ZombieSoundRadius) or 0)
    if radius > 0 then addSound(nil, math.floor(args.x), math.floor(args.y), math.floor(args.z), radius, radius) end
    local to = {}
    if isServer() then
        local players = getOnlinePlayers()
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            local dx, dy = p:getX() - args.x, p:getY() - args.y
            if dx * dx + dy * dy <= Fx.RANGE * Fx.RANGE then
                sendServerCommand(p, M.MODULE, "fx", args)
                to[#to + 1] = p:getUsername()
            end
        end
    elseif M.Effects then
        M.Effects.play(args)
        to[1] = "local"
    end
    M.log(string.format("FX kind=%s x=%d y=%d z=%d sound=%d to=%s", kind, math.floor(args.x), math.floor(args.y),
        math.floor(args.z), radius, #to > 0 and table.concat(to, ",") or "-"))
end

return Fx
