-- Vehicle Capsule (client): draw the effects the server announces (server/MinidoracatVehicleCapsule/Fx.lua).
--   pack / unpack: cartoon smoke (8 frames, 150 ms each), a ~0.2 s flash and a local sound.
--   flight: the capsule flies from the thrower to the landing point in 0.5 s, then lies there until the pop.
-- Drawn over the world in screen space (isoToScreenX/Y + UIManager.DrawTexture); nothing touches the world, so no
-- zombie reacts (the server's addSound is the only sound zombies hear). Timing is wall clock, not frames.
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule
local Effects = { active = {}, played = 0 }
M.Effects = Effects

local FRAME_MS, FRAMES = 150, 8
local FLIGHT_MS, REST_MS = 500, 1500
local SMOKE_PX, CAPSULE_PX, ARC_PX = 384, 40, 90
local SOUNDS = { pack = "VehicleCapsulePack", unpack = "VehicleCapsulePop" }
local smoke, capsule

local function textures()
    if smoke then return end
    smoke = {}
    for i = 1, FRAMES do smoke[i] = getTexture("media/textures/MinidoracatVehicleCapsule/smoke_" .. i .. ".png") end
    capsule = getTexture("media/textures/Item_MinidoracatVehicleCapsuleLoaded.png")
end

-- No removal inside pairs: Kahlua tables are Java maps.
local function removeAll(ids)
    for _, id in ipairs(ids) do Effects.active[id] = nil end
end

function Effects.play(args)
    if not args.id or Effects.active[args.id] then return end -- split screen: one copy per message
    textures()
    local fx = { kind = args.kind, t0 = getTimestampMs(), x = args.x, y = args.y, z = args.z,
        x0 = args.x0, y0 = args.y0, z0 = args.z0 }
    Effects.played = Effects.played + 1
    if fx.kind ~= "flight" then
        local landed = {} -- the capsule lying on the landing point pops
        for id, other in pairs(Effects.active) do
            if other.kind == "flight" and math.floor(other.x) == math.floor(fx.x)
                and math.floor(other.y) == math.floor(fx.y) then
                landed[#landed + 1] = id
            end
        end
        removeAll(landed)
        local x, y, z = math.floor(fx.x), math.floor(fx.y), math.floor(fx.z)
        getCell():addLamppost(IsoLightSource.new(x, y, z, 1, 0.95, 0.8, 8, 6))
        getSoundManager():PlayWorldSoundImpl(SOUNDS[fx.kind] or SOUNDS.unpack, false, x, y, z, 0, 20, 1, false)
    end
    Effects.active[args.id] = fx
end

local function drawSmoke(p, fx, age)
    local tex = smoke[math.floor(age / FRAME_MS) + 1]
    if not tex then return end
    local w = SMOKE_PX / getCore():getZoom(p)
    local sx, sy = isoToScreenX(p, fx.x, fx.y, fx.z), isoToScreenY(p, fx.x, fx.y, fx.z)
    UIManager.DrawTexture(tex, sx - w / 2, sy - w * 0.7, w, w, 1)
end

local function drawFlight(p, fx, age)
    if not capsule then return end
    local t = math.min(age / FLIGHT_MS, 1)
    local x, y, z = fx.x0 + (fx.x - fx.x0) * t, fx.y0 + (fx.y - fx.y0) * t, fx.z0 + (fx.z - fx.z0) * t
    local zoom = getCore():getZoom(p)
    local w = CAPSULE_PX / zoom
    local lift = (4 * t * (1 - t) * ARC_PX + 30 * (1 - t)) / zoom -- arc, leaving from hand height
    local sx, sy = isoToScreenX(p, x, y, z), isoToScreenY(p, x, y, z) - lift
    UIManager.DrawTexture(capsule, sx - w / 2, sy - w / 2, w, w, 1)
end

Events.OnPreUIDraw.Add(function()
    local now, done = getTimestampMs(), nil
    for id, fx in pairs(Effects.active) do
        local age = now - fx.t0
        if age >= (fx.kind == "flight" and FLIGHT_MS + REST_MS or FRAME_MS * FRAMES) then
            done = done or {}
            done[#done + 1] = id
        else
            for p = 0, getNumActivePlayers() - 1 do
                if getSpecificPlayer(p) then
                    if fx.kind == "flight" then drawFlight(p, fx, age) else drawSmoke(p, fx, age) end
                end
            end
        end
    end
    if done then removeAll(done) end
end)

return Effects
