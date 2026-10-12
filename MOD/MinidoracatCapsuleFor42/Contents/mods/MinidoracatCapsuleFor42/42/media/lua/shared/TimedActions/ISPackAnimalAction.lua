require "TimedActions/ISBaseTimedAction"
require "MinidoracatCapsule/Rules"

-- Pack a live animal into the player's empty capsule. Built like vanilla ISPickupAnimal (the animal's movement is held
-- while the action runs, released when it stops) and this mod's ISPackVehicleAction (the client sends a "packAnimal"
-- intent when it queues this, client/MinidoracatCapsule/Menu.lua; complete() runs on the server, SP: locally, and
-- checks everything again in MinidoracatCapsule.Play.packAnimal). MP runs start/stop on the client and
-- serverStart/serverStop on the server (NetTimedAction.java:95-115), so the hold is set on both sides.
ISPackAnimalAction = ISBaseTimedAction:derive("ISPackAnimalAction")
local M = MinidoracatCapsule

local function hold(animal, on)
    local b = animal and animal:getBehavior()
    if b then b:setBlockMovement(on) end
end

function ISPackAnimalAction:isValid()
    return M.Rules.animalWhyNot(self.character, self.animal) == nil
end

function ISPackAnimalAction:waitToStart()
    self.character:faceThisObject(self.animal)
    return self.character:shouldBeTurning()
end

function ISPackAnimalAction:update()
    self.character:faceThisObject(self.animal)
    self.character:setMetabolicTarget(Metabolics.LightWork)
end

function ISPackAnimalAction:start()
    hold(self.animal, true)
    self:setActionAnim("Loot")
    self.character:SetVariable("LootPosition", "Low")
end

function ISPackAnimalAction:stop()
    hold(self.animal, false)
    ISBaseTimedAction.stop(self)
end

function ISPackAnimalAction:perform()
    hold(self.animal, false)
    ISBaseTimedAction.perform(self)
end

function ISPackAnimalAction:serverStart()
    hold(self.animal, true)
end

function ISPackAnimalAction:serverStop()
    hold(self.animal, false)
end

-- A refused pack leaves the animal in the world: let it walk again.
function ISPackAnimalAction:complete()
    local ok = M.Play.packAnimal(self.character, self.animal, self.typeId)
    if not ok then hold(self.animal, false) end
    return ok
end

function ISPackAnimalAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return M.Rules.PACK_SECONDS * 50 -- 1 unit = 20 ms (NetTimedAction.getDuration)
end

-- MP: the server rebuilds the action from these parameters (NetTimedAction.java:36-55); typeId (the capsule type picked
-- in the menu) is SP only, MP sends it with the intent.
function ISPackAnimalAction:new(character, animal)
    local o = ISBaseTimedAction.new(self, character)
    o.animal = animal
    o.maxTime = o:getDuration()
    return o
end
