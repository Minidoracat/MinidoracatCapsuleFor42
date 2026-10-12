-- Universal Capsule (client): context menu entries.
--   * "Pack into capsule" at the end of the vanilla outside-vehicle menu. With empty capsules of two or more types it
--     opens a submenu, one entry per type ("Steam Capsule x2"); with one type or none it is a single entry. Each entry
--     has a tooltip that checks every requirement (permission, engine off and nobody inside, a capsule of an enabled
--     type) and says how to fix it; greyed out until all pass. Without permission it stays clickable with a minus
--     icon, and a click shows the reason in a toast; no red text (it drops to 1.09:1 on the hover highlight, design
--     vcap-types-1012 review). The tooltip background is opaque. The server checks again in complete().
--   * A loaded capsule: "Throw capsule" when the player carries it, "Press the button" when it lies on the ground
--     (inventory/loot window and world right click). Both open the landing cursor (ThrowCursor.lua).
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Notify"
require "MinidoracatCapsule/ThrowCursor"
require "Vehicles/ISUI/ISVehicleMenu"
require "TimedActions/ISPackVehicleAction"
local M = MinidoracatCapsule
local Rules, Notify = M.Rules, M.Notify
local Menu = {}
M.Menu = Menu

local function tr(key, ...) return getText("IGUI_MinidoracatCapsule_" .. key, ...) end

local IDLE = { OCCUPIED = true, ENGINE_RUNNING = true }

local MISS_ICON = "media/ui/Moodle_internal_minus_red.png" -- the tooltip's own mark for a failed row (Notify.row)

local function typeName(t) return M.Info.itemName(t.empty) end

-- Tooltip rows for packing this vehicle with a capsule of type t (nil: the player carries none). single: the only
-- entry, so a passing capsule row names the type. Returns ok (every row passes), rich text, may (permission),
-- permission text.
function Menu.packTooltip(player, vehicle, t, single)
    local may, permText = Notify.permission(player, vehicle)
    local idle = not vehicle:isEngineRunning() and not Rules.occupied(vehicle)
    local other = Rules.vehicleWhyNot(player, vehicle)
    if IDLE[other] then other = nil end
    local text = Notify.row(may, permText) .. Notify.row(idle, tr(idle and "Idle" or "IdleNo"))
    local capsule = t ~= nil and Rules.typeOn(t)
    if not t then
        text = text .. Notify.row(false, tr("HasCapsuleNo"))
    elseif not capsule then
        text = text .. Notify.row(false, tr("TypeOffRow", typeName(t)))
    elseif single then
        text = text .. Notify.row(true, tr("HasCapsuleKind", typeName(t)))
    end
    if other then text = text .. Notify.row(false, Notify.reason(other)) end
    text = text .. " <RGB:1,1,1> <LINE> " .. tr("PackInfo", Rules.cargoCount(vehicle), Rules.PACK_SECONDS)
    return may and idle and capsule and other == nil, text, may, permText
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
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(title)
    tip.description = text
    tip.maxLineWidth = 420 -- keeps a long "how to fix" row on the line of its mark
    tip.backgroundColor.a = 1 -- opaque under the vanilla 0.7 layer; ISToolTip:reset puts it back for the pool
    option.toolTip = tip
    return option
end

function Menu.addPack(playerNum, context, vehicle)
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    local label = getText("ContextMenu_MinidoracatCapsule_Pack")
    local kinds = Rules.emptyTypes(player)
    if #kinds < 2 then
        return addPackOption(context, player, vehicle, kinds[1] and kinds[1].type, label, label, true)
    end
    local parent = context:addOption(label)
    local sub = ISContextMenu:getNew(context)
    context:addSubMenu(parent, sub)
    for _, k in ipairs(kinds) do
        local name = typeName(k.type)
        addPackOption(sub, player, vehicle, k.type, getText("ContextMenu_MinidoracatCapsule_PackKind", name, k.n),
            tr("PackInto", name), false)
    end
    return parent
end

local fillOutside = ISVehicleMenu.FillMenuOutsideVehicle
function ISVehicleMenu.FillMenuOutsideVehicle(playerNum, context, vehicle, test)
    local r = fillOutside(playerNum, context, vehicle, test)
    if test then return r end
    Menu.addPack(playerNum, context, vehicle)
    return r
end

-- ------------------------------------------------------------------ capsule
function Menu.onThrow(player, item) M.ThrowCursor.open(player, item, "throw") end

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
