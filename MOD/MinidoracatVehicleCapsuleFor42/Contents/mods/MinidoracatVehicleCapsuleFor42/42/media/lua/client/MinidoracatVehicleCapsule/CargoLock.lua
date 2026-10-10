-- Vehicle Capsule (client): cargo inside a loaded capsule stays there until the vehicle is unpacked. This is the
-- player-facing side only; the server puts back anything that leaves (server/MinidoracatVehicleCapsule/Guard.lua).
--   * every vanilla way of taking an item out (drag, loot all, grab, eat/drink/equip/reload/craft, which all move the
--     item into the main inventory first) is an ISInventoryTransferAction: refuse it and say why;
--   * the context menu of cargo shows only that hint;
--   * capsule containers are not offered to crafting and building (ISInventoryPaneContextMenu.getContainers).
-- Sandbox AllowCargoTakeOut opens the first two for a capsule whose record is a confirmed PACKED one (Rules.cargoOpen);
-- crafting and building still use nothing inside a capsule, and nothing can be put in (MaxItemSize).
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Rules"
require "MinidoracatVehicleCapsule/Info"
require "TimedActions/ISInventoryTransferAction"
require "ISUI/ISInventoryPaneContextMenu"
local M = MinidoracatVehicleCapsule
local CargoLock = { notices = 0 }
M.CargoLock = CargoLock

local lastHalo = 0
function CargoLock.notify(player)
    CargoLock.notices = CargoLock.notices + 1
    local now = getTimestampMs()
    if player and now - lastHalo > 1500 then
        lastHalo = now
        HaloTextHelper.addBadText(player, getText("IGUI_MinidoracatVehicleCapsule_CargoLocked"))
    end
end

local function takeOut() return M.Rules.sandbox().AllowCargoTakeOut == true end

-- capsuleId -> may its cargo leave, from the last answer. Kept while Info asks again after the server rewrote the
-- record (every take does), so a loot-all queue is not cut off halfway.
local open = {}

-- True when every loaded capsule around `container` lets its cargo out. Closed until the first answer arrives.
function CargoLock.open(container)
    if not takeOut() then return false end
    local holder = container and container:getContainingItem()
    while holder do
        if holder:getFullType() == M.ITEM_LOADED then
            local id = holder:getID()
            local r = M.Info.get(id)
            if r then open[id] = r.ok == true and M.Rules.cargoOpen(r) end
            if open[id] ~= true then return false end
        end
        local c = holder:getContainer()
        holder = c and c:getContainingItem()
    end
    return true
end

local isValid = ISInventoryTransferAction.isValid
function ISInventoryTransferAction:isValid()
    if self.srcContainer and M.isCapsuleContainer(self.srcContainer) and not CargoLock.open(self.srcContainer) then
        CargoLock.notify(self.character)
        return false
    end
    return isValid(self)
end

local getContainers = ISInventoryPaneContextMenu.getContainers
ISInventoryPaneContextMenu.getContainers = function(character)
    return M.withoutCapsules(getContainers(character))
end

Events.OnFillInventoryObjectContextMenu.Add(function(playerNum, context, items)
    local locked = false
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if M.inCapsule(item) and not CargoLock.open(item:getContainer()) then locked = true; break end
    end
    if not locked then return end
    context:clear()
    local option = context:addOption(getText("IGUI_MinidoracatVehicleCapsule_CargoLocked"))
    option.notAvailable = true
end)

return CargoLock
