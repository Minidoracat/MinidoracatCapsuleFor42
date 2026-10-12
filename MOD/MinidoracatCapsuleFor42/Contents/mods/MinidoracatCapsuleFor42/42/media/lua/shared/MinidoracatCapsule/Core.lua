-- Universal Capsule: shared constants and helpers.
MinidoracatCapsule = MinidoracatCapsule or {}
local M = MinidoracatCapsule

M.MOD_ID = "MinidoracatCapsuleFor42"
M.MODULE = "MinidoracatCapsule" -- client command module and item module
M.LOG_PREFIX = "[MinidoracatCapsuleFor42] "
M.PACK_RANGE = 8 -- tiles between player and vehicle (pack) or player and capsule on the ground (unpack)

-- The capsule types, in the order of the admin "Types" tab, the sandbox page and the style index the server sends with
-- an effect (Fx.broadcast args.style). id gives the rest: items Capsule<id> / LoadedCapsule<id>
-- (scripts/MinidoracatCapsule_items.txt), icons Item_MinidoracatCapsule<id>[Loaded].png
-- (scripts/assets/build_capsule.py), sandbox Type<id> (packing with it allowed) and Type<id>Loot (in loot), the
-- look-and-sound line Tooltip_MinidoracatCapsule_Look_<id>. Look and sounds (client/Effects.lua): smoke =
-- texture name prefix of the frames <prefix>1.png .. <prefix><frames>.png (cartoon: scripts/assets/build_smoke.py, the
-- others design_smoke.py), px = drawn size at zoom 1, anchor = share of that size above the ground point, flash =
-- light colour; throw / pop / pack / button = sound script names (media/scripts/MinidoracatCapsule_sounds.txt,
-- takes in scripts/assets/build_sfx.py). Only the looks and sounds differ (user, design vcap-types-1012).
M.TYPES = {
    { id = "Cartoon", smoke = "smoke_", frames = 8, frameMs = 150, px = 384, anchor = 0.7, flash = { 1, 0.95, 0.8 },
        throw = "UniversalCapsuleThrow", pop = "UniversalCapsulePop", pack = "UniversalCapsulePack",
        button = "UniversalCapsuleButton" },
    { id = "Real", smoke = "smoke_S1_", frames = 16, frameMs = 90, px = 576, anchor = 0.66, flash = { 0.85, 0.85, 0.82 },
        throw = "UniversalCapsuleThrowReal", pop = "UniversalCapsulePopReal", pack = "UniversalCapsulePackReal",
        button = "UniversalCapsuleButtonReal" },
    { id = "Dust", smoke = "smoke_S2_", frames = 16, frameMs = 90, px = 576, anchor = 0.62, flash = { 1, 0.85, 0.6 },
        throw = "UniversalCapsuleThrowReal2", pop = "UniversalCapsulePopHeavyDrop", pack = "UniversalCapsulePackHeavy",
        button = "UniversalCapsuleButtonDust" },
    { id = "Steam", smoke = "smoke_S3_", frames = 12, frameMs = 85, px = 480, anchor = 0.7, flash = { 0.9, 0.95, 1 },
        throw = "UniversalCapsuleThrowSteam", pop = "UniversalCapsulePopSteam", pack = "UniversalCapsulePackSteam",
        button = "UniversalCapsuleButtonSwitch" },
    { id = "SciFi", smoke = "smoke_S4_", frames = 12, frameMs = 85, px = 416, anchor = 0.78, flash = { 0.5, 0.9, 1 },
        throw = "UniversalCapsuleThrowSci", pop = "UniversalCapsulePopSci", pack = "UniversalCapsulePackSci",
        button = "UniversalCapsuleButtonSci" },
    { id = "Magic", smoke = "smoke_S5_", frames = 15, frameMs = 90, px = 576, anchor = 0.66, flash = { 0.95, 0.8, 1 },
        throw = "UniversalCapsuleThrowMagic", pop = "UniversalCapsulePopMagic", pack = "UniversalCapsulePackMagic",
        button = "UniversalCapsuleButtonMagic" },
    { id = "Shock", smoke = "smoke_S6_", frames = 18, frameMs = 90, px = 672, anchor = 0.75, flash = { 1, 0.85, 0.6 },
        throw = "UniversalCapsuleThrowShock", pop = "UniversalCapsulePopExplosion", pack = "UniversalCapsulePackShock",
        button = "UniversalCapsuleButtonShock" },
}
M.EMPTY, M.LOADED, M.TYPE_BY_ID = {}, {}, {} -- empty / loaded full type -> type; id -> type
for i, t in ipairs(M.TYPES) do
    t.index = i
    t.empty = M.MODULE .. ".Capsule" .. t.id
    t.loaded = M.MODULE .. ".LoadedCapsule" .. t.id
    M.EMPTY[t.empty], M.LOADED[t.loaded], M.TYPE_BY_ID[t.id] = t, t, t
end

-- The type of a capsule item (empty or loaded), or nil for anything else.
function M.typeOf(item)
    local ft = item and item:getFullType()
    return ft and (M.EMPTY[ft] or M.LOADED[ft])
end

function M.isLoaded(item)
    return item ~= nil and M.LOADED[item:getFullType()] ~= nil
end

function M.isEmpty(item)
    return item ~= nil and M.EMPTY[item:getFullType()] ~= nil
end

function M.log(msg)
    print(M.LOG_PREFIX .. tostring(msg))
end

-- True for a loaded capsule's own inventory and for any container nested inside one (a bag in the cargo).
function M.isCapsuleContainer(container)
    local holder = container and container:getContainingItem()
    if not holder then return false end
    return M.isLoaded(holder) or M.isCapsuleContainer(holder:getContainer())
end

-- True for cargo: an item anywhere inside a loaded capsule. The capsule itself is not inside one.
function M.inCapsule(item)
    return item ~= nil and M.isCapsuleContainer(item:getContainer())
end

-- Drops capsule containers from a java ArrayList<ItemContainer> in place (crafting and building input lists).
function M.withoutCapsules(list)
    if not list then return list end
    for i = list:size() - 1, 0, -1 do
        local c = list:get(i)
        if M.isCapsuleContainer(c) then list:remove(c) end
    end
    return list
end

-- Same rule as VehicleManager O.isAdmin: Capability.ManipulateVehicle on a dedicated server; SP host is admin.
function M.isAdmin(player)
    if player == nil then return false end
    if not isServer() then return not isClient() end
    if Capability == nil then return false end
    return checkPermissions(player, Capability.ManipulateVehicle) == true
end

return M
