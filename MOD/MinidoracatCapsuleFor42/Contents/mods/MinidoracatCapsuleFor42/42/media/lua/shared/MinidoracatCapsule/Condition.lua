-- Universal Capsule: condition numbers of a recorded vehicle from its parts in the Query.summary format
-- ({ id, c = condition, i = item, ic = item condition, u = uses, a = amount }). The tooltip and the preview word
-- them (client Info.details: part and item names in the player's language); the Economy listing shows the numbers
-- (server Trade.view), so a buyer reads what the tooltip says.
require "MinidoracatCapsule/Core"
local M = MinidoracatCapsule
local Condition = {}
M.Condition = Condition

-- Vanilla parts that hold an item: a slot without one is missing. Parts not listed here and holding an item are
-- extras from a vehicle mod (KI5 bull bars, armor): listed as modifications.
local SLOT_PREFIX = { "Door", "EngineDoor", "TrunkDoor", "Window", "Windshield", "Tire", "Brake", "Suspension", "Seat",
    "Battery", "GasTank", "Muffler", "Headlight", "TruckBed", "Radio" }
local FIXED = { Engine = true, GloveBox = true, Heater = true, PassengerCompartment = true, TrunkDoorOpened = true,
    TruckBedOpen = true, lightbar = true }
local BODY_PREFIX = { "Door", "EngineDoor", "TrunkDoor", "Window", "Windshield" }

local function startsWithAny(id, list)
    for _, p in ipairs(list) do
        if string.sub(id, 1, #p) == p then return true end
    end
    return false
end

-- VehiclePart.getNumberByCondition (VehiclePart.java:335-339): a gas tank holds less when damaged.
local function byCondition(number, cond)
    cond = cond + 20 * (100 - cond) / 100
    return math.floor(math.max(5, number * cond / 100) * 100 + 0.5) / 100
end

local capacityOf = {}
local function maxCapacity(fullType)
    if capacityOf[fullType] == nil then
        local item = instanceItem(fullType)
        capacityOf[fullType] = item and item:getMaxCapacity() or -1
    end
    return capacityOf[fullType]
end

-- { engine, body, battery, fuel, fuelCap, missing = { part id, ... }, mods = { item full type, ... } }; a number is
-- nil when the vehicle has no such part (no gas tank: no fuel).
function Condition.of(parts)
    local d = { missing = {}, mods = {} }
    local bodySum, bodyN = 0, 0
    for _, p in ipairs(parts or {}) do
        local id = tostring(p.id)
        if id == "Engine" then d.engine = p.c end
        if id == "Battery" and p.i and p.u then d.battery = math.floor(p.u * 100 + 0.5) end
        if id == "GasTank" and p.i then
            d.fuel = p.a
            local cap = maxCapacity(p.i)
            if cap and cap > 0 then d.fuelCap = math.floor(byCondition(cap, p.ic or 100)) end
        end
        if p.i and startsWithAny(id, BODY_PREFIX) then bodySum, bodyN = bodySum + (p.c or 0), bodyN + 1 end
        if not p.i and startsWithAny(id, SLOT_PREFIX) then
            d.missing[#d.missing + 1] = id
        elseif p.i and not FIXED[id] and not startsWithAny(id, SLOT_PREFIX) then
            d.mods[#d.mods + 1] = p.i
        end
    end
    if bodyN > 0 then d.body = math.floor(bodySum / bodyN + 0.5) end
    return d
end

return Condition
