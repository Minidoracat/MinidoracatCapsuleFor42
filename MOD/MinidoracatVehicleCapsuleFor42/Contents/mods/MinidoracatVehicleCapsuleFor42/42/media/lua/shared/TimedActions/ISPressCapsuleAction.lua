require "TimedActions/ISBaseTimedAction"
require "MinidoracatVehicleCapsule/Core"

-- Press the button of a loaded capsule lying on the ground (one too heavy to pick up): its vehicle appears at
-- (x, y, z), within Rules.PRESS_RANGE of the capsule. Passes the capsule by id: an item on the ground has no
-- container the network can name. The client sends a "press" intent when it queues this; complete() runs on the
-- server (SP: locally) and finds the capsule again (MinidoracatVehicleCapsule.Play.press).
ISPressCapsuleAction = ISBaseTimedAction:derive("ISPressCapsuleAction")
local M = MinidoracatVehicleCapsule

-- self.item (client only) is the capsule picked from the menu; the server looks it up by id in complete().
function ISPressCapsuleAction:isValid()
    return self.item == nil or self.item:getWorldItem() ~= nil
end

function ISPressCapsuleAction:waitToStart()
    local wo = self.item and self.item:getWorldItem()
    if wo then self.character:faceThisObject(wo) end
    return self.character:shouldBeTurning()
end

function ISPressCapsuleAction:start()
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
    if not isServer() then
        local c = self.character
        local sound = M.Effects and M.Effects.style().button or "VehicleCapsuleButton" -- client/Effects.lua
        getSoundManager():PlayWorldSoundImpl(sound, false, math.floor(c:getX()), math.floor(c:getY()),
            math.floor(c:getZ()), 0, 10, 1, false)
    end
end

function ISPressCapsuleAction:complete()
    return M.Play.press(self.character, self.capsuleId, self.x, self.y, self.z)
end

function ISPressCapsuleAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return 40
end

-- MP: the server rebuilds the action from these parameters (NetTimedAction.java:36-55).
function ISPressCapsuleAction:new(character, capsuleId, x, y, z)
    local o = ISBaseTimedAction.new(self, character)
    o.capsuleId = capsuleId
    o.x, o.y, o.z = x, y, z
    o.maxTime = o:getDuration()
    return o
end
