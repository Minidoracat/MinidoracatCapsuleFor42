-- Vehicle Capsule: crafting never uses inputs or tools that are cargo inside a loaded capsule (client, SP, server).
-- HandcraftLogic reads only the containers it is given, not bags inside them (CraftRecipeManager.java:274-282), and the
-- server builds it from the container list the client sent (ISHandcraftAction.serverStart). So the server drops
-- capsule containers itself, and refuses a recipe whose inputs are still cargo (manual input lists also come from the
-- client). The client hides capsule containers from the craft/build UI (client/MinidoracatVehicleCapsule/CargoLock.lua).
require "MinidoracatVehicleCapsule/Core"
require "Entity/TimedActions/ISHandcraftAction"
local M = MinidoracatVehicleCapsule

local serverStart, start, performRecipe = ISHandcraftAction.serverStart, ISHandcraftAction.start,
    ISHandcraftAction.performRecipe

function ISHandcraftAction:serverStart()
    M.withoutCapsules(self.containers)
    return serverStart(self)
end

function ISHandcraftAction:start()
    M.withoutCapsules(self.containers)
    return start(self)
end

-- Runs where the recipe is performed (server in MP, SP); canPerformCurrentRecipe fills the input list it will use.
function ISHandcraftAction:performRecipe()
    if self.logic then
        self.logic:canPerformCurrentRecipe()
        local data = self.logic:getRecipeData()
        local items = data and data:getAllInputItems()
        for i = 0, (items and items:size() or 0) - 1 do
            if M.inCapsule(items:get(i)) then
                M.log("craft " .. tostring(self.craftRecipe and self.craftRecipe:getName()) .. " by "
                    .. tostring(self.character and self.character:getUsername()) .. " refused: an input is capsule cargo")
                return
            end
        end
    end
    return performRecipe(self)
end
