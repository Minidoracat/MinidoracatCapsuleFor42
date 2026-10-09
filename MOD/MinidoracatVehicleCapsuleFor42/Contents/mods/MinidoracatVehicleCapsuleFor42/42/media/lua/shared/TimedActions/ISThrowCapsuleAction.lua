require "TimedActions/ISBaseTimedAction"

-- Throw a capsule at (x, y, z). Plays the vanilla Molotov clip through our own action node
-- (AnimSets/player/actions/MinidoracatVehicleCapsuleThrow.xml): the vanilla Throw node only
-- matches Weapon=throwing, and a capsule is a container, not a HandWeapon.
-- CapsuleRelease (30%) is when the item leaves the hand; CapsuleEnd (75%) ends the action.
-- The dedicated server plays no animations, so serverStart emulates both events with the same
-- timing (emulateAnimEventOnce, LuaManager.java:12237; same approach as Workshop 3809762635).
-- Spike stage: the item is not consumed and nothing spawns; release and complete only log.
ISThrowCapsuleAction = ISBaseTimedAction:derive("ISThrowCapsuleAction")

ISThrowCapsuleAction.ANIM = "MinidoracatVehicleCapsuleThrow"

-- Bob_AttackThrowMolotov lasts 7040 ticks at 4800 ticks/s; the node plays it at m_SpeedScale 0.8.
local ANIM_MS = 7040 / 4800 / 0.8 * 1000
local RELEASE_PC, END_PC = 0.3, 0.75
local LOG = "[MinidoracatVehicleCapsule] "

local function side()
    if isServer() then return "server" end
    return isClient() and "client" or "sp"
end

function ISThrowCapsuleAction:isValid()
    return self.item ~= nil and self.character:getInventory():containsID(self.item:getID())
end

-- faceLocation sets the direction at once but the body (animAngle) turns over up to ~700 ms, and the clip
-- only plays after that turn while the server emulates the release from start(): wait for the body
-- (E2E throw-mp 1010c: 40 deg late = release 250 ms late, 170 deg = 680 ms; server completed before the
-- client clip reached CapsuleEnd). The 1.5 s cap only keeps an odd state from blocking the queue.
function ISThrowCapsuleAction:waitToStart()
    local c = self.character
    c:faceLocation(self.x, self.y)
    self.waitMs = self.waitMs or getTimestampMs()
    if getTimestampMs() - self.waitMs > 1500 then return false end
    local diff = math.abs(c:getAnimAngle() - c:getDirectionAngle()) % 360
    return c:shouldBeTurning() or math.min(diff, 360 - diff) > 5
end

function ISThrowCapsuleAction:update()
    self.character:faceLocation(self.x, self.y)
end

function ISThrowCapsuleAction:start()
    self.startMs = getTimestampMs()
    self:setActionAnim(ISThrowCapsuleAction.ANIM)
    self:setOverrideHandModels(self.item, self.character:getSecondaryHandItem())
end

function ISThrowCapsuleAction:serverStart()
    self.startMs = getTimestampMs()
    emulateAnimEventOnce(self.netAction, math.floor(ANIM_MS * RELEASE_PC), "CapsuleRelease", nil)
    emulateAnimEventOnce(self.netAction, math.floor(ANIM_MS * END_PC), "CapsuleEnd", nil)
end

function ISThrowCapsuleAction:animEvent(event, parameter)
    if event == "CapsuleRelease" then
        if self.released then return end
        self.released = getTimestampMs()
        print(string.format("%srelease side=%s player=%s item=%d sinceStart=%d ts=%d", LOG, side(),
            self.character:getUsername(), self.item and self.item:getID() or -1,
            self.released - (self.startMs or self.released), self.released))
        if not isServer() then
            self:setOverrideHandModels(nil, self.character:getSecondaryHandItem())
        end
    elseif event == "CapsuleEnd" and self.maxTime == -1 then
        if isServer() then
            self.netAction:forceComplete()
        else
            self:forceComplete()
        end
    end
end

-- MP: server only (LuaTimedActionNew.java:163-170); SP: local.
function ISThrowCapsuleAction:complete()
    if not self:isValid() then
        print(LOG .. "complete rejected: item not in inventory")
        return false
    end
    local now = getTimestampMs()
    print(string.format("%scomplete side=%s ts=%d player=%s item=%d target=%d,%d,%d sinceStart=%d released=%s",
        LOG, side(), now, self.character:getUsername(), self.item:getID(), self.x, self.y, self.z,
        now - (self.startMs or now), tostring(self.released ~= nil)))
    return true
end

function ISThrowCapsuleAction:getDuration()
    if self.character:isTimedActionInstant() then return 1 end
    return -1 -- ends at CapsuleEnd
end

-- MP: the server rebuilds the action from the fields named like these parameters (NetTimedAction.java:36-55).
function ISThrowCapsuleAction:new(character, item, x, y, z)
    local o = ISBaseTimedAction.new(self, character)
    o.item = item
    o.x, o.y, o.z = x, y, z
    o.stopOnWalk = true
    o.stopOnRun = true
    o.useProgressBar = false
    o.maxTime = o:getDuration()
    return o
end
