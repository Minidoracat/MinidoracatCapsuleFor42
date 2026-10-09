-- Vehicle Capsule (client): cargo inside a loaded capsule stays there until the vehicle is unpacked. This is the
-- player-facing side only; the server puts back anything that leaves (server/MinidoracatVehicleCapsule/Guard.lua).
--   * every vanilla way of taking an item out (drag, loot all, grab, eat/drink/equip/reload/craft, which all move the
--     item into the main inventory first) is an ISInventoryTransferAction: refuse it and say why;
--   * the context menu of cargo shows only that hint;
--   * capsule containers are not offered to crafting and building (ISInventoryPaneContextMenu.getContainers).
require "MinidoracatVehicleCapsule/Core"
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

local isValid = ISInventoryTransferAction.isValid
function ISInventoryTransferAction:isValid()
    if self.srcContainer and M.isCapsuleContainer(self.srcContainer) then
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
    local cargo = false
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if M.inCapsule(item) then cargo = true; break end
    end
    if not cargo then return end
    context:clear()
    local option = context:addOption(getText("IGUI_MinidoracatVehicleCapsule_CargoLocked"))
    option.notAvailable = true
end)

return CargoLock
