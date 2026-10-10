-- Vehicle Capsule (client): context menu entries.
--   * "Pack into capsule" at the end of the vanilla outside-vehicle menu, with a tooltip that checks each
--     requirement (permission, engine off and nobody inside, an empty capsule) and says how to fix it; greyed out
--     until all pass. The server checks again in complete() (PlayerCommands.lua).
--   * A loaded capsule: "Throw capsule" when the player carries it, "Press the button" when it lies on the ground
--     (inventory/loot window and world right click). Both open the landing cursor (ThrowCursor.lua).
require "MinidoracatVehicleCapsule/Rules"
require "MinidoracatVehicleCapsule/Notify"
require "MinidoracatVehicleCapsule/ThrowCursor"
require "Vehicles/ISUI/ISVehicleMenu"
require "TimedActions/ISPackVehicleAction"
local M = MinidoracatVehicleCapsule
local Rules, Notify = M.Rules, M.Notify
local Menu = {}
M.Menu = Menu

local function tr(key, ...) return getText("IGUI_MinidoracatVehicleCapsule_" .. key, ...) end

local PERM_TEXT = { VM = "PermOwner", KEY = "PermKey", ADMIN = "PermAdmin", ANY = "PermAny" }
local IDLE = { OCCUPIED = true, ENGINE_RUNNING = true }

-- Tooltip rows for packing this vehicle; returns ok (every row passes), rich text.
function Menu.packTooltip(player, vehicle)
    local may, mode = Rules.mayPack(player, vehicle)
    local idle = not vehicle:isEngineRunning() and not Rules.occupied(vehicle)
    local capsule = Rules.emptyCapsule(player) ~= nil
    local other = Rules.vehicleWhyNot(player, vehicle)
    if IDLE[other] then other = nil end
    local key = PERM_TEXT[mode]
    local text = Notify.row(may, tr(may and key or key .. "No"))
        .. Notify.row(idle, tr(idle and "Idle" or "IdleNo"))
        .. Notify.row(capsule, tr(capsule and "HasCapsule" or "HasCapsuleNo"))
    if other then text = text .. Notify.row(false, Notify.reason(other)) end
    text = text .. " <RGB:1,1,1> <LINE> " .. tr("PackInfo", Rules.cargoCount(vehicle), Rules.PACK_SECONDS)
    return may and idle and capsule and other == nil, text
end

function Menu.capsuleName(vehicle)
    return tr("LoadedName", ISVehicleMenu.getVehicleDisplayName(vehicle))
end

-- Walks next to the vehicle, tells the server who asks (with the capsule name in this client's language) and packs.
function Menu.onPack(player, vehicle)
    local name = Menu.capsuleName(vehicle)
    if player:DistToSquared(vehicle) > 9 then ISTimedActionQueue.add(ISPathFindAction:pathToVehicleAdjacent(player, vehicle)) end
    if isClient() then
        sendClientCommand(player, M.MODULE, "intent", { kind = "pack", id = vehicle:getId(), name = name })
    end
    local action = ISPackVehicleAction:new(player, vehicle)
    action.capsuleName = name -- SP: complete() runs on this very object
    ISTimedActionQueue.add(action)
    return action
end

function Menu.addPack(playerNum, context, vehicle)
    local player = getSpecificPlayer(playerNum)
    if not player or player:getVehicle() then return end
    local label = getText("ContextMenu_MinidoracatVehicleCapsule_Pack")
    local option = context:addOption(label, player, Menu.onPack, vehicle)
    local ok, text = Menu.packTooltip(player, vehicle)
    local tip = ISWorldObjectContextMenu.addToolTip()
    tip:setName(label)
    tip.description = text
    tip.maxLineWidth = 420 -- keeps a long "how to fix" row on the line of its mark
    option.toolTip = tip
    option.notAvailable = not ok
    return option
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
        return context:addOption(getText("ContextMenu_MinidoracatVehicleCapsule_Press"), player, Menu.onPress, item)
    end
    if player:getInventory():containsRecursive(item) then
        return context:addOption(getText("ContextMenu_MinidoracatVehicleCapsule_Throw"), player, Menu.onThrow, item)
    end
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local player = getSpecificPlayer(playerNum)
    if not player then return end
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if item:getFullType() == M.ITEM_LOADED and not M.inCapsule(item) then
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
                if item and item:getFullType() == M.ITEM_LOADED then
                    addCapsule(context, player, item)
                    return
                end
            end
        end
    end
end)

return Menu
