-- Vehicle Capsule (client): draw the effects the server announces (server/MinidoracatVehicleCapsule/Fx.lua).
--   pack / unpack: smoke frames, a ~0.2 s flash and a local sound.
--   flight: the capsule flies from the thrower to the landing point in 0.5 s whatever the distance, with a whoosh at
--   the thrower (one clip fits every throw), then lies there until the pop.
-- The look and the sounds follow the sandbox option EffectStyle (Effects.STYLES), read on this client: the server
-- sends every sandbox change to all clients (GameServer.receiveSandboxOptions, GameServer.java:1710-1726), so they all
-- draw the same style. The admin panel can also play one style here only (Effects.preview).
-- Drawn over the world in screen space (isoToScreenX/Y + UIManager.DrawTexture); nothing touches the world, so no
-- zombie reacts (the server's addSound is the only sound zombies hear). Timing is wall clock, not frames.
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Rules"
local M = MinidoracatVehicleCapsule
local Effects = { active = {}, played = 0 }
M.Effects = Effects

local FLIGHT_MS, REST_MS = 500, 1500
local CAPSULE_PX, ARC_PX = 40, 90
local DIR = "media/textures/MinidoracatVehicleCapsule/"

-- EffectStyle n is STYLES[n], in the order of the option's _option<n> names. smoke: texture name prefix of the
-- frames <prefix>1.png .. <prefix><frames>.png (cartoon: scripts/assets/build_smoke.py, the others design_smoke.py);
-- px: drawn size at zoom 1; anchor: share of that size above the ground point; flash: light colour; throw / pop /
-- pack / button: sound script names (media/scripts/MinidoracatVehicleCapsule_sounds.txt, takes in build_sfx.py).
Effects.STYLES = {
    { id = "Cartoon", smoke = "smoke_", frames = 8, frameMs = 150, px = 384, anchor = 0.7, flash = { 1, 0.95, 0.8 },
        throw = "VehicleCapsuleThrow", pop = "VehicleCapsulePop", pack = "VehicleCapsulePack",
        button = "VehicleCapsuleButton" },
    { id = "Real", smoke = "smoke_S1_", frames = 16, frameMs = 90, px = 576, anchor = 0.66, flash = { 0.85, 0.85, 0.82 },
        throw = "VehicleCapsuleThrowReal", pop = "VehicleCapsulePopReal", pack = "VehicleCapsulePackReal",
        button = "VehicleCapsuleButtonReal" },
    { id = "Dust", smoke = "smoke_S2_", frames = 16, frameMs = 90, px = 576, anchor = 0.62, flash = { 1, 0.85, 0.6 },
        throw = "VehicleCapsuleThrowReal2", pop = "VehicleCapsulePopHeavyDrop", pack = "VehicleCapsulePackHeavy",
        button = "VehicleCapsuleButtonReal" },
    { id = "Steam", smoke = "smoke_S3_", frames = 12, frameMs = 85, px = 480, anchor = 0.7, flash = { 0.9, 0.95, 1 },
        throw = "VehicleCapsuleThrowReal", pop = "VehicleCapsulePopSteam", pack = "VehicleCapsulePackSteam",
        button = "VehicleCapsuleButtonSwitch" },
    { id = "SciFi", smoke = "smoke_S4_", frames = 12, frameMs = 85, px = 416, anchor = 0.78, flash = { 0.5, 0.9, 1 },
        throw = "VehicleCapsuleThrowSci", pop = "VehicleCapsulePopSci", pack = "VehicleCapsulePackSci",
        button = "VehicleCapsuleButtonSci" },
    { id = "Magic", smoke = "smoke_S5_", frames = 15, frameMs = 90, px = 576, anchor = 0.66, flash = { 0.95, 0.8, 1 },
        throw = "VehicleCapsuleThrowMagic", pop = "VehicleCapsulePopMagic", pack = "VehicleCapsulePackMagic",
        button = "VehicleCapsuleButtonMagic" },
    { id = "Shock", smoke = "smoke_S6_", frames = 12, frameMs = 85, px = 448, anchor = 0.6, flash = { 1, 0.97, 0.9 },
        throw = "VehicleCapsuleThrowReal2", pop = "VehicleCapsulePopSmokeGrenade", pack = "VehicleCapsulePackReal",
        button = "VehicleCapsuleButtonReal" },
}
local SOUND = { pack = "pack", unpack = "pop", flight = "throw" }
local capsule
local pending = {} -- { at, args }: plays the preview queued for later
local previews = 0

-- The style of the sandbox option (the cartoon one for an unknown value).
function Effects.style()
    return Effects.STYLES[tonumber(M.Rules.sandbox().EffectStyle)] or Effects.STYLES[1]
end

-- Frames of a style, loaded when it first plays: only the styles in use take texture memory.
local function frames(st)
    if not st.tex then
        st.tex = {}
        for i = 1, st.frames do st.tex[i] = getTexture(DIR .. st.smoke .. i .. ".png") end
    end
    return st.tex
end

-- No removal inside pairs: Kahlua tables are Java maps.
local function removeAll(ids)
    for _, id in ipairs(ids) do Effects.active[id] = nil end
end

-- args from the server: id, kind, x, y, z (flight: x0, y0, z0 too). The preview adds style (index into STYLES) and
-- onDone (called when the effect ends).
function Effects.play(args)
    if not args.id or Effects.active[args.id] then return end -- split screen: one copy per message
    local st = Effects.STYLES[args.style] or Effects.style()
    if not capsule then capsule = getTexture("media/textures/Item_MinidoracatVehicleCapsuleLoaded.png") end
    -- the frames load now, at the throw too, so the pop does not wait for them
    local fx = { kind = args.kind, st = st, tex = frames(st), t0 = getTimestampMs(), x = args.x, y = args.y, z = args.z,
        x0 = args.x0, y0 = args.y0, z0 = args.z0, onDone = args.onDone }
    Effects.played = Effects.played + 1
    local sound = st[SOUND[fx.kind] or "pop"]
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
        local c = st.flash
        getCell():addLamppost(IsoLightSource.new(x, y, z, c[1], c[2], c[3], 8, 6))
        getSoundManager():PlayWorldSoundImpl(sound, false, x, y, z, 0, 20, 1, false)
    else
        getSoundManager():PlayWorldSoundImpl(sound, false, math.floor(fx.x0), math.floor(fx.y0), math.floor(fx.z0),
            0, 20, 1, false)
    end
    Effects.active[args.id] = fx
end

-- The admin panel's preview, on this client only: a capsule thrown in style n from the player to (x, y, z) (its
-- whoosh and flight, then the pop, the flash and the smoke); onDone() when the smoke is gone.
function Effects.preview(n, player, x, y, z, onDone)
    previews = previews + 1
    local id = "preview" .. previews
    Effects.play({ id = id .. "f", kind = "flight", style = n, x0 = player:getX(), y0 = player:getY(),
        z0 = player:getZ(), x = x, y = y, z = z })
    pending[#pending + 1] = { at = getTimestampMs() + FLIGHT_MS,
        args = { id = id .. "u", kind = "unpack", style = n, x = x, y = y, z = z, onDone = onDone } }
end

local function drawSmoke(p, fx, age)
    local st = fx.st
    local tex = fx.tex[math.floor(age / st.frameMs) + 1]
    if not tex then return end
    local w = st.px / getCore():getZoom(p)
    local sx, sy = isoToScreenX(p, fx.x, fx.y, fx.z), isoToScreenY(p, fx.x, fx.y, fx.z)
    UIManager.DrawTexture(tex, sx - w / 2, sy - w * st.anchor, w, w, 1)
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
    if #pending > 0 then
        local due = {}
        for i = #pending, 1, -1 do
            if now >= pending[i].at then due[#due + 1] = table.remove(pending, i).args end
        end
        for _, args in ipairs(due) do Effects.play(args) end
    end
    for id, fx in pairs(Effects.active) do
        local age = now - fx.t0
        if age >= (fx.kind == "flight" and FLIGHT_MS + REST_MS or fx.st.frameMs * fx.st.frames) then
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
    if done then
        for _, id in ipairs(done) do
            local onDone = Effects.active[id].onDone
            Effects.active[id] = nil
            if onDone then onDone() end
        end
    end
end)

return Effects
