-- Universal Capsule: read a live animal into a plain table (the record's `animal`, JSON-storable) and build it again.
-- Nothing of the animal travels in the capsule: a vanilla Base.Animal item would weigh the animal (a cow ~104), and a
-- container item always weighs its contents (AGENTS.md). Ported from the feasibility spike vcap-animal-*-1012b.
-- Not written back (no Lua setter; reset or recomputed): lastMilkTimer, eggsToday, clutchSize, petTimer,
-- lastPregnancyTime, lastImpregnateTime, milkRemoved, migrationGroup. In MP every client rolls its own coat colour
-- (vanilla); the server keeps the stored one.
if isClient() then return end
require "MinidoracatCapsule/Core"
local M = MinidoracatCapsule
local Animal = {}
M.Animal = Animal

local function allele(x)
    return { v = x:getCurrentValue(), r = x:getTrueRatioValue(), dom = x:isDominant(), used = x:isUsed(),
        gd = x:getGeneticDisorder() }
end

local function genome(a)
    local out, list = {}, a:getFullGenomeList()
    for i = 0, list:size() - 1 do
        local g = list:get(i)
        out[g:getName()] = { a1 = allele(g:getAllele1()), a2 = allele(g:getAllele2()) }
    end
    return out
end

-- Everything restore writes back, plus what the tooltip shows. modData keeps string keys with primitive values only.
-- accept: the animal's acceptance of `player` (the one packing it).
function Animal.capture(a, player)
    local d = a:getData()
    local dis, gl = {}, a:getGeneticDisorder()
    for i = 0, gl:size() - 1 do dis[#dis + 1] = tostring(gl:get(i)) end
    local md = {}
    for k, v in pairs(a:getModData()) do
        local t = type(v)
        if type(k) == "string" and (t == "string" or t == "number" or t == "boolean") then md[k] = v end
    end
    local vis = a:getAnimalVisual()
    return {
        type = a:getAnimalType(), breed = a:getBreed():getName(), female = a:isFemale(),
        age = d:getAge(), hours = a:getHoursSurvived(), size = d:getSize(), weight = d:getWeight(),
        health = a:getHealth(), hunger = a:getStats():get(CharacterStat.HUNGER),
        thirst = a:getStats():get(CharacterStat.THIRST), stress = a:getStress(),
        name = a:getCustomName(), animalId = a:getAnimalID(), wild = a:isWild(),
        milkCan = d:canHaveMilk(), milk = d:getMilkQuantity(), milkMax = d:getMaxMilkActual(),
        wool = d:getWoolQuantity(), pregnant = d:isPregnant(), pregTime = d:getPregnancyTime(),
        fert = d:isFertilized(), fertTime = d:getFertilizedTime(),
        skin = vis and vis:getSkinTexture() or nil,
        accept = player and a:getAcceptanceLevel(player) or nil,
        genome = genome(a), disorders = dis, modData = md,
    }
end

local function setAllele(x, s)
    if not s then return end
    x:setCurrentValue(s.v)
    x:setTrueRatioValue(s.r)
    x:setDominant(s.dom == true)
    x:setUsed(s.used == true)
    x:setGeneticDisorder(s.gd)
end

-- Builds the animal on square sq and puts it in the world in this tick, so a client's first request already gets the
-- whole state. Returns the animal, or nil plus "BLOCKED" (IsoAnimal.new skips init on water: no animal type).
-- Order matters: genome before age (data.init uses genes); age before size and weight (setAgeDebug re-inits both,
-- IsoAnimal.java:1608-1612); wild before stress (setWild(true) rolls stress 50-80, IsoAnimal.java:3214-3225);
-- maxMilkActual before milk (setMilkQuantity clamps to it, and lowering milk while canHaveMilk stamps the last
-- milking, AnimalData.java:1536-1549). No time passes in a capsule: nothing is simulated for the time away.
function Animal.restore(s, sq, player)
    local a = IsoAnimal.new(getCell(), sq:getX(), sq:getY(), sq:getZ(), s.type, s.breed)
    if not a:getAnimalType() then return nil, "BLOCKED" end
    a:setFemale(s.female == true)
    local list = a:getFullGenomeList()
    for i = 0, list:size() - 1 do
        local g = list:get(i)
        local gs = s.genome and s.genome[g:getName()]
        if gs then
            setAllele(g:getAllele1(), gs.a1)
            setAllele(g:getAllele2(), gs.a2)
        end
    end
    AnimalGene.checkGeneticDisorder(a)
    a:setAgeDebug(s.age)
    a:setHoursSurvived(s.hours)
    local d = a:getData()
    d:setSize(s.size)
    d:setWeight(s.weight)
    a:setHealth(s.health)
    a:getStats():set(CharacterStat.HUNGER, s.hunger)
    a:getStats():set(CharacterStat.THIRST, s.thirst)
    a:setWild(s.wild == true)
    a:setDebugStress(s.stress)
    d:setCanHaveMilk(false)
    d:setMaxMilkActual(s.milkMax)
    d:setMilkQuantity(s.milk)
    d:setMaxMilkActual(s.milkMax)
    d:setCanHaveMilk(s.milkCan == true)
    d:setWoolQuantity(s.wool, true)
    d:setPregnant(s.pregnant == true)
    d:setPregnancyTime(s.pregTime)
    d:setFertilized(s.fert == true)
    d:setFertilizedTime(s.fertTime)
    if s.name then a:setCustomName(s.name) end
    a:setAnimalID(s.animalId)
    if s.skin then a:getAnimalVisual():setSkinTextureName(s.skin) end
    local md = a:getModData()
    for k, v in pairs(s.modData or {}) do md[k] = v end
    if player and s.accept then a:setDebugAcceptance(player, s.accept) end
    a:addToWorld()
    return a
end

-- What clients may see of a recorded animal (tooltip, admin panel, Economy listing). Pregnancy and fertilization only
-- with `breeding` (vanilla sends them to Husbandry > 2 only, NetworkPlayerAI.java:212-222).
function Animal.view(s, breeding)
    if type(s) ~= "table" then return nil end
    local v = { type = s.type, breed = s.breed, name = s.name, female = s.female, age = s.age, weight = s.weight,
        health = s.health, wild = s.wild, wool = s.wool }
    if s.milkCan then v.milk, v.milkMax = s.milk, s.milkMax end
    if breeding then v.pregnant, v.fert = s.pregnant, s.fert end
    return v
end

return Animal
