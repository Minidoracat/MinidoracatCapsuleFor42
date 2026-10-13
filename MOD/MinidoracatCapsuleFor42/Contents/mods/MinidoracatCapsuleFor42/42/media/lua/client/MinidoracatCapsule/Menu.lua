-- Universal Capsule (client): context menu entries.
--   * "Pack into capsule" at the end of the vanilla outside-vehicle menu, and in a live animal's own submenu (the
--     vanilla animal menu, AnimalContextMenu.doMenu). With empty capsules of two or more types it opens a submenu,
--     one entry per type ("Steam Capsule x2"); with one type or none it is a single entry. Each entry has a tooltip
--     that checks every requirement (vehicle: permission, engine off and nobody inside; animal: packing animals on,
--     its state; both: a capsule of an enabled type) and says how to fix it; greyed out until all pass. Without
--     permission a vehicle entry stays clickable with a minus icon, and a click shows the reason in a toast; no red
--     text (it drops to 1.09:1 on the hover highlight, design vcap-types-1012 review). The tooltip background is
--     opaque. The server checks again in complete().
--   * A loaded capsule: "Throw capsule" when the player carries it, "Press the button" when it lies on the ground
--     (inventory/loot window and world right click). Both open the landing cursor (ThrowCursor.lua).
--   * An empty capsule the player carries: "Throw to capture" (inventory window), the capture cursor: an animal or a
--     vehicle at the spot is packed into it when it lands, under the same rules as the menus above.
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Notify"
require "MinidoracatCapsule/ThrowCursor"
require "Vehicles/ISUI/ISVehicleMenu"
require "ISUI/Animal/ISAnimalContextMenu"
require "TimedActions/ISPackVehicleAction"
require "TimedActions/ISPackAnimalAction"
local M = MinidoracatCapsule
local Rules, Notify = M.Rules, M.Notify
local Menu = {}
M.Menu = Menu

local function tr(key, ...) return getText("IGUI_MinidoracatCapsule_" .. key, ...) end

local IDLE = { OCCUPIED = true, ENGINE_RUNNING = true }

local MISS_ICON = "media/ui/Moodle_internal_minus_red.png" -- the tooltip's own mark for a failed row (Notify.row)

local function typeName(t) return M.Info.itemName(t.empty) end

-- The capsule row of a pack tooltip and whether it passes. t: the type of the entry (nil: the player carries none);
-- single: the only entry, so a passing row names the type.
local function capsuleRow(t, single)
    local ok = t ~= nil and Rules.typeOn(t)
    if not t then return false, Notify.row(false, tr("HasCapsuleNo")) end
    if not ok then return false, Notify.row(false, tr("TypeOffRow", typeName(t))) end
    return true, single and Notify.row(true, tr("HasCapsuleKind", typeName(t))) or ""
end

-- Tooltip rows for packing this vehicle with a capsule of type t (nil: the player carries none). single: the only
-- entry, so a passing capsule row names the type. Returns ok (every row passes), rich text, may (permission),
-- permission text.
function Menu.packTooltip(player, vehicle, t, single)
    local may, permText = Notify.permission(player, vehicle)
    local idle = not vehicle:isEngineRunning() and not Rules.occupied(vehicle)
    local other = Rules.vehicleWhyNot(player, vehicle)
    if IDLE[other] then other = nil end
    local text = Notify.row(may, permText) .. Notify.row(idle, tr(idle and "Idle" or "IdleNo"))
    local capsule, row = capsuleRow(t, single)
    text = text .. row
    if other then text = text .. Notify.row(false, Notify.reason(other)) end
    text = text .. " <RGB:1,1,1> <LINE> " .. tr("PackInfo", Rules.cargoCount(vehicle), Rules.PACK_SECONDS)
    return may and idle and capsule and other == nil, text, may, permText
end

-- Tooltip rows for packing this animal with a capsule of type t: packing animals switched off, the capsule, then the
-- animal's own state (held, tied, gone), and for a wild one the chance it is caught. Anyone may pack an animal.
-- Returns ok, rich text.
function Menu.packAnimalTooltip(player, animal, t, single)
    local why = Rules.animalWhyNot(player, animal)
    local text = why == "ANIMALS_OFF" and Notify.row(false, Notify.reason(why)) or ""
    local capsule, row = capsuleRow(t, single)
    text = text .. row
    if why and why ~= "ANIMALS_OFF" then text = text .. Notify.row(false, Notify.reason(why)) end
    text = text .. Notify.chanceRow(animal) .. " <RGB:1,1,1> <LINE> " .. tr("PackAnimalInfo", Rules.PACK_SECONDS)
    return why == nil and capsule, text
end

-- Clicked without permission: the reason as a toast, kept up long enough to read (review: 3 s was too short).
function Menu.onDenied(text)
    Notify.toast(Notify.reason("NOT_ALLOWED"), text, true, 8000)
end

-- Walks next to the vehicle, tells the server who asks and with which capsule type, and packs.
function Menu.onPack(player, vehicle, t)
    if player:DistToSquared(vehicle) > 9 then ISTimedActionQueue.add(ISPathFindAction:pathToVehicleAdjacent(player, vehicle)) end
    if isClient() then
        sendClientCommand(player, M.MODULE, "intent", { kind = "pack", id = vehicle:getId(), type = t.id })
    end
    local action = ISPackVehicleAction:new(player, vehicle)
    action.typeId = t.id -- SP: complete() runs on this very object
    ISTimedActionQueue.add(action)
    return action
end

-- The pack tooltip box: title, rich text, opaque.
local function tooltip(option, title, text)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(title)
    tip.description = text
    tip.maxLineWidth = 420 -- keeps a long "how to fix" row on the line of its mark
    tip.backgroundColor.a = 1 -- opaque under the vanilla 0.7 layer; ISToolTip:reset puts it back for the pool
    option.toolTip = tip
    return option
end

local function addPackOption(menu, player, vehicle, t, label, title, single)
    local ok, text, may, permText = Menu.packTooltip(player, vehicle, t, single)
    local option
    if may then
        option = menu:addOption(label, player, Menu.onPack, vehicle, t)
        option.notAvailable = not ok
    else
        option = menu:addOption(label, permText, Menu.onDenied)
        option.iconTexture = getTexture(MISS_ICON)
    end
    return tooltip(option, title, text)
end

-- "Pack into capsule" in context: one entry, or a submenu with one entry per capsule type the player carries.
-- addOne(menu, t, label, title, single) adds an entry.
local function addEntries(context, player, addOne)
    local label = getText("ContextMenu_MinidoracatCapsule_Pack")
    local kinds = Rules.emptyTypes(player)
    if #kinds < 2 then return addOne(context, kinds[1] and kinds[1].type, label, label, true) end
    local parent = context:addOption(label)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)
    for _, k in ipairs(kinds) do
        local name = typeName(k.type)
        addOne(sub, k.type, getText("ContextMenu_MinidoracatCapsule_PackKind", name, k.n), tr("PackInto", name), false)
    end
    return parent
end

function Menu.addPack(playerNum, context, vehicle)
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    return addEntries(context, player, function(menu, t, label, title, single)
        return addPackOption(menu, player, vehicle, t, label, title, single)
    end)
end

-- Walks next to the animal (vanilla AnimalContextMenu.onPickupAnimal), tells the server who asks, which animal (its
-- online id) and with which capsule type, and packs.
function Menu.onPackAnimal(player, animal, t)
    animal:stopAllMovementNow()
    if not luautils.walkAdj(player, animal:getSquare()) then return nil end
    if isClient() then
        sendClientCommand(player, M.MODULE, "intent", { kind = "packAnimal", id = animal:getOnlineID(), type = t.id })
    end
    local action = ISPackAnimalAction:new(player, animal)
    action.typeId = t.id -- SP: complete() runs on this very object
    ISTimedActionQueue.add(action)
    return action
end

-- The animal's own submenu (vanilla doMenu adds one option per animal, highlighted with onHighlightParams = { animal },
-- its submenu holding the animal actions), or nil. Newest first: pooled options can keep old fields.
local function animalMenu(context, animal)
    local opts = context.options or {}
    for i = #opts, 1, -1 do
        local opt = opts[i]
        if opt.subOption and type(opt.onHighlightParams) == "table" and opt.onHighlightParams[1] == animal then
            return context:getSubMenu(opt.subOption)
        end
    end
    return nil
end

function Menu.addPackAnimal(playerNum, context, animal)
    local player = getSpecificPlayer(playerNum)
    local menu = player and not player:getVehicle() and animalMenu(context, animal)
    if not menu then return nil end
    return addEntries(menu, player, function(sub, t, label, title, single)
        local ok, text = Menu.packAnimalTooltip(player, animal, t, single)
        local option = sub:addOption(label, player, Menu.onPackAnimal, animal, t)
        option.notAvailable = not ok
        return tooltip(option, title, text)
    end)
end

local fillOutside = ISVehicleMenu.FillMenuOutsideVehicle
function ISVehicleMenu.FillMenuOutsideVehicle(playerNum, context, vehicle, test)
    local r = fillOutside(playerNum, context, vehicle, test)
    if test then return r end
    Menu.addPack(playerNum, context, vehicle)
    return r
end

local doMenu = AnimalContextMenu.doMenu
function AnimalContextMenu.doMenu(player, context, animal, test)
    local r = doMenu(player, context, animal, test)
    if not test then Menu.addPackAnimal(player, context, animal) end
    return r
end

-- ------------------------------------------------------------------ capsule
function Menu.onThrow(player, item) M.ThrowCursor.open(player, item, "throw") end
function Menu.onCapture(player, item) M.ThrowCursor.open(player, item, "capture") end

-- Walk next to the capsule first, then pick the spot: the player then stands where the cursor can see them.
function Menu.onPress(player, item)
    local wo = item:getWorldItem()
    local sq = wo and wo:getSquare()
    if not (sq and luautils.walkAdj(player, sq)) then return end
    local queue = ISTimedActionQueue.getTimedActionQueue(player).queue
    local walk = queue[#queue]
    if walk and walk.Type == "ISWalkToTimedAction" then
        walk:setOnComplete(M.ThrowCursor.open, player, item, "press")
    else
        M.ThrowCursor.open(player, item, "press")
    end
end

local function addCapsule(context, player, item)
    if item:getWorldItem() then
        return context:addOption(getText("ContextMenu_MinidoracatCapsule_Press"), player, Menu.onPress, item)
    end
    if player:getInventory():containsRecursive(item) then
        return context:addOption(getText("ContextMenu_MinidoracatCapsule_Throw"), player, Menu.onThrow, item)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if M.isLoaded(item) and not M.inCapsule(item) then
            addCapsule(context, player, item)
            return
        end
        if M.isEmpty(item) and not M.inCapsule(item) and not item:getWorldItem()
            and player:getInventory():containsRecursive(item) then
            context:addOption(getText("ContextMenu_MinidoracatCapsule_Capture"), player, Menu.onCapture, item)
            return
        end
    end
end)

Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    if test then return end
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    local seen = {}
    for _, obj in ipairs(worldobjects) do
        local sq = obj:getSquare()
        if sq and not seen[sq] then
            seen[sq] = true
            local wos = sq:getWorldObjects()
            for i = 0, wos:size() - 1 do
                local item = wos:get(i):getItem()
                if item and M.isLoaded(item) then
                    addCapsule(context, player, item)
                    return
                end
            end
        end
    end
end)

return Menu
