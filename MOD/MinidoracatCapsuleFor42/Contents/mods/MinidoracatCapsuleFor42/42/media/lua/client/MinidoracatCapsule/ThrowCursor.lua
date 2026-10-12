-- Universal Capsule (client): the landing cursor for "throw capsule" and "press the button", the admin panel's
-- "restore at a picked spot", and "throw to capture" (an empty capsule at an animal or a vehicle). A build cursor
-- (ISBuildingObject, like vanilla ISFarmingCursorMouse): the engine calls isValid/render every frame and create on a
-- left click (only when valid); right click opens the world menu, which drops the drag (ISWorldObjectContextMenu
-- createMenu -> setDrag(nil)); a gamepad moves it and presses A / B. The vehicle's ground (a capture: its target) is
-- drawn tile by tile in the good / bad highlight colour with a tooltip that says why. The server checks the same rules
-- again (Footprint.lua, Rules.lua), so this is only what the player sees.
require "MinidoracatCapsule/Rules"
require "MinidoracatCapsule/Footprint"
require "MinidoracatCapsule/Notify"
require "TimedActions/ISThrowCapsuleAction"
require "TimedActions/ISPressCapsuleAction"
local M = MinidoracatCapsule
local Rules, Footprint, Notify = M.Rules, M.Footprint, M.Notify
-- Methods live here; the ISBuildingObject subclass is derived on first use (Cursor.new): ISBuildingObject is in the
-- server folder, which an MP client loads after the client folder, so requiring it from here fails at load time.
local Cursor = {}
M.ThrowCursor = Cursor
local Class

-- capsuleId -> { kind, script, animal } (Play.capsuleInfo: a vehicle script, or kind "animal" with its names), false =
-- the server has no record
local infos = {}
local HINT = { throw = "IGUI_MinidoracatCapsule_HintThrow", press = "IGUI_MinidoracatCapsule_HintPress",
    restore = "IGUI_MinidoracatCapsule_HintRestore", capture = "IGUI_MinidoracatCapsule_HintThrow" }
local PROMPT = { throw = "ContextMenu_MinidoracatCapsule_Throw", press = "ContextMenu_MinidoracatCapsule_Press",
    restore = "UI_MinidoracatCapsule_Restore", capture = "ContextMenu_MinidoracatCapsule_Capture" }
local CAPTURE_MS = 250 -- a capture re-judges its square this often (the target moves; a vehicle's body costs a scan)

function Cursor.onInfo(args)
    if not args.capsuleId then return end
    infos[args.capsuleId] = args.ok and { kind = args.kind, script = args.script, animal = args.animal } or false
end

-- extra: more intent fields (a capture's target).
local function sendIntent(player, kind, id, extra)
    if not isClient() then return end
    local args = { kind = kind, id = id }
    for k, v in pairs(extra or {}) do args[k] = v end
    sendClientCommand(player, M.MODULE, "intent", args)
end

-- mode: "throw" (capsule in the player's inventory), "press" (capsule on the ground) or "capture" (an empty capsule in
-- the player's inventory).
function Cursor.open(player, item, mode)
    local id = item:getID()
    if mode ~= "capture" and type(infos[id]) ~= "table" then
        infos[id] = nil
        if isClient() then
            sendClientCommand(player, M.MODULE, "capsuleInfo", { capsuleId = id })
        elseif M.Play then
            M.Play.capsuleInfo(player, id)
        end
    end
    local cursor = Cursor.new(player, item, mode)
    Cursor.current = cursor
    getCell():setDrag(cursor, player:getPlayerNum())
    return cursor
end

-- Admin restore ("Restore vehicle" / "Restore animal"): rec (the detail: script, or kind "animal") goes where the admin
-- clicks, a vehicle facing away from them, on any loaded square (no throw range, no line of sight). `home` { x, y, z }
-- is the recorded spot, the default choice: its ground is drawn as a white frame (as the vehicle would stand if
-- clicked there; an animal's one square) and the tooltip names it. Both boxes and both tooltip lines are made here:
-- render runs every frame. onDone(x, y, z, dir) after a click, onDone(nil) when the cursor goes away without one.
function Cursor.openRestore(player, rec, home, onDone)
    local cursor = Cursor.new(player, nil, "restore")
    cursor.rec, cursor.onDone = { kind = rec.kind, script = rec.script, animal = rec.animal }, onDone
    local ns, ew
    if rec.kind == "animal" then
        if home then ns = select(2, Footprint.animalClear(home.x, home.y, home.z or 0)) end
        ew = ns
    else
        local w, l = Footprint.size(rec.script and getScriptManager():getVehicle(rec.script))
        if home and w then ns, ew = Footprint.box(home.x, home.y, "N", w, l), Footprint.box(home.x, home.y, "E", w, l) end
    end
    if ns then
        local x, y = tostring(home.x), tostring(home.y)
        cursor.home = { x = home.x, y = home.y, z = home.z or 0, ns = ns, ew = ew,
            near = getText("IGUI_MinidoracatCapsule_RestoreHome", x, y),
            far = getText("IGUI_MinidoracatCapsule_RestoreHomeFar", x, y) }
    end
    Cursor.current = cursor
    getCell():setDrag(cursor, player:getPlayerNum())
    return cursor
end

-- Where the capsule starts from: the thrower, or the pressed capsule's square.
function Cursor:origin()
    if self.mode == "press" then
        local wo = self.item:getWorldItem()
        local sq = wo and wo:getSquare()
        if not sq then return nil end
        return sq:getX() + 0.5, sq:getY() + 0.5, sq:getZ(), Rules.PRESS_RANGE, false
    end
    local c = self.character
    if self.mode == "restore" then return c:getX(), c:getY(), c:getZ() end
    return c:getX(), c:getY(), c:getZ(), Rules.THROW_RANGE, true
end

-- The name the tooltip gives an animal or a vehicle in the world.
local function thingName(thing, isAnimal)
    if isAnimal then
        return M.Info.animalName({ type = thing:getAnimalType(), breed = thing:getBreed():getName(),
            name = thing:getCustomName() })
    end
    return Notify.vehicleName(thing:getScriptName())
end

-- Capture: the animal or vehicle on or next to square (Footprint.target) and the reason it can't be taken (the same
-- rules as packing it by menu, Rules.captureWhyNot), or nil. Keeps self.target (thing, animal, name) and self.cells
-- (the target's squares, drawn in render). Judged at most every CAPTURE_MS per square.
function Cursor:judgeCapture(square)
    local x, y, z, now = square:getX(), square:getY(), square:getZ(), getTimestampMs()
    local last = self.last
    if last and last.x == x and last.y == y and now - last.at < CAPTURE_MS then return last.why end
    local thing, animal = Footprint.target(x, y, z)
    self.target, self.cells = nil, {}
    if thing then
        self.target = { thing = thing, animal = animal, name = thingName(thing, animal) }
        if animal then
            self.cells[1] = thing:getSquare()
        else
            for _, sq in ipairs(Footprint.squares(Footprint.bodyBox(thing), z)) do
                if sq:getVehicleContainer() == thing then self.cells[#self.cells + 1] = sq end
            end
        end
    end
    local c = self.character
    local why = Footprint.reach(c:getX(), c:getY(), c:getZ(), x, y, z, Rules.THROW_RANGE, true)
    if not why and not thing then why = "NO_TARGET" end
    if not why then why = Rules.captureWhyNot(c, thing, animal, M.typeOf(self.item)) end
    self.last = { x = x, y = y, at = now, why = why }
    return why
end

-- Reason the vehicle (or animal) cannot land on square, or nil; keeps self.box / self.dir for render.
function Cursor:judge(square)
    self.box = nil
    if self.mode == "capture" then return self:judgeCapture(square) end
    local rec = self.rec or infos[self.capsuleId]
    if rec == nil then return "LOADING" end
    if rec == false then return "NO_SNAPSHOT" end
    local ox, oy, oz, range, sight = self:origin()
    if not ox then return "NO_CAPSULE" end
    local x, y, z = square:getX(), square:getY(), square:getZ()
    self.dir = Footprint.dirOf(x - ox, y - oy)
    local clear, box
    if rec.kind == "animal" then
        clear, box = Footprint.animalClear(x, y, z)
    else
        local sc = getScriptManager():getVehicle(rec.script)
        if not sc then return "SCRIPT_MISSING" end
        clear, box = Footprint.clear(sc, x, y, z, self.dir)
    end
    self.box = box
    return (range and Footprint.reach(ox, oy, oz, x, y, z, range, sight))
        or (box and Rules.safehouseWhyNot(self.character, box, z)) or clear
end

function Cursor:isValid(square)
    self.why = self:judge(square)
    return self.why == nil
end

function Cursor:render(x, y, z, square)
    local c = self.why == nil and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
    local sprite = self:getFloorCursorSprite()
    local h = self.home
    if h and getCell():getGridSquare(h.x, h.y, h.z) then
        local p = self.character
        local d = Footprint.dirOf(h.x - p:getX(), h.y - p:getY()) -- the facing a click there would give
        local hb = (d == "E" or d == "W") and h.ew or h.ns
        for bx = hb.x1, hb.x2 do
            for by = hb.y1, hb.y2 do sprite:RenderGhostTileColor(bx, by, h.z, 1, 1, 1, 0.3) end
        end
    end
    local b = self.box
    if b then
        for bx = b.x1, b.x2 do
            for by = b.y1, b.y2 do sprite:RenderGhostTileColor(bx, by, z, c:getR(), c:getG(), c:getB(), 0.5) end
        end
    end
    for _, sq in ipairs(self.mode == "capture" and self.cells or {}) do
        sprite:RenderGhostTileColor(sq:getX(), sq:getY(), sq:getZ(), c:getR(), c:getG(), c:getB(), 0.5)
    end
    sprite:RenderGhostTileColor(x, y, z, 1, 1, 1, 0.8)
    self:renderTooltip(square)
end

function Cursor:tooltipText()
    local text
    if self.mode == "capture" then
        local tgt = self.target
        if self.why == nil then
            text = Notify.row(true, getText("IGUI_MinidoracatCapsule_CaptureFits", tgt.name))
        else
            text = (tgt and " <RGB:1,1,1> " .. getText("IGUI_MinidoracatCapsule_CaptureTarget", tgt.name) .. " <LINE> " or "")
                .. Notify.row(false, getText("IGUI_MinidoracatCapsule_CaptureNoFit", Notify.reason(self.why)))
        end
    elseif self.why == nil then
        local rec = self.rec or infos[self.capsuleId]
        local name = rec.kind == "animal" and M.Info.animalName(rec.animal) or Notify.vehicleName(rec.script)
        text = Notify.row(true, getText("IGUI_MinidoracatCapsule_Fits", name))
    elseif self.why == "LOADING" then
        text = " " .. getText("IGUI_MinidoracatCapsule_Loading") .. " <LINE> "
    else
        text = Notify.row(false, getText("IGUI_MinidoracatCapsule_NoFit", Notify.reason(self.why, true)))
    end
    local h = self.home
    if h then
        text = text .. " <RGB:0.85,0.85,0.85> " .. (getCell():getGridSquare(h.x, h.y, h.z) and h.near or h.far) .. " <LINE> "
    end
    if not self.joypad then
        text = text .. " <RGB:1,1,1> " .. getText(HINT[self.mode])
    end
    return text
end

function Cursor:renderTooltip(square)
    local text = self:tooltipText()
    if not self.tooltip then
        self.tooltip = ISWorldObjectContextMenu.addToolTip()
        self.tooltip:setVisible(true)
        self.tooltip:addToUIManager()
        self.tooltip.followMouse = not self.joypad
        self.tooltip.maxLineWidth = 1000
        self.tooltip.backgroundColor.a = 1 -- opaque under the vanilla 0.7 layer: the red reason row stays readable
        -- over the world (3.35:1 before, design vcap-types-1012 review); addToolTip resets it for the next user
    end
    self.tooltip.description = text
    if self.joypad and square then
        self.tooltip:setX(isoToScreenX(self.player, square:getX(), square:getY(), square:getZ()))
        self.tooltip:setY(isoToScreenY(self.player, square:getX(), square:getY(), square:getZ()))
    end
end

function Cursor:hideTooltip()
    if self.tooltip then
        self.tooltip:removeFromUIManager()
        self.tooltip:setVisible(false)
        self.tooltip = nil
    end
end

-- Called by IsoCell.setDrag when the cursor goes away (after a click too: dragNilAfterPlace).
function Cursor:deactivate()
    self:hideTooltip()
    if Cursor.current == self then Cursor.current = nil end
    if self.onDone and not self.picked then
        self.picked = true
        self.onDone(nil)
    end
end

-- Left click / A on a valid square (ISBuildingObject:tryBuild with skipBuildAction).
function Cursor:create(x, y, z)
    self:hideTooltip()
    if self.mode == "restore" then
        self.picked = true
        self.onDone(x, y, z, self.dir)
        return
    end
    Cursor.queue(self.character, self.item, self.mode, x, y, z, self.target)
end

-- Queues the throw, the capture or the press (also used by E2E scenarios). The intent tells the server who really
-- asked; a capture's intent also names its target ({ thing, animal }: what the cursor judged): the animal's online id
-- or the vehicle id (SP: the action keeps the object, complete() runs on this very action).
function Cursor.queue(player, item, mode, x, y, z, target)
    local id = item:getID()
    if mode == "press" then
        local wo = item:getWorldItem()
        if wo and wo:getSquare() then luautils.walkAdj(player, wo:getSquare(), true) end -- normally already beside it
        sendIntent(player, "press", id)
        local action = ISPressCapsuleAction:new(player, id, x, y, z)
        action.item = item
        ISTimedActionQueue.add(action)
        return action
    end
    ISInventoryPaneContextMenu.transferIfNeeded(player, item)
    local capture
    if mode == "capture" and target then
        local kind = target.animal and "animal" or "vehicle"
        capture = { kind = kind, thing = target.thing }
        sendIntent(player, "capture", id, { target = kind,
            tid = target.animal and target.thing:getOnlineID() or target.thing:getId() })
    else
        sendIntent(player, "throw", id)
    end
    local action = ISThrowCapsuleAction:new(player, item, x, y, z)
    action.capture = capture
    ISTimedActionQueue.add(action)
    return action
end

function Cursor:getAPrompt()
    if self.why ~= nil then return nil end
    return getText(PROMPT[self.mode])
end

function Cursor:getLBPrompt() return nil end
function Cursor:getRBPrompt() return nil end

function Cursor.new(player, item, mode)
    if not Class then
        Class = ISBuildingObject:derive("MinidoracatCapsuleCursor")
        for k, v in pairs(Cursor) do Class[k] = v end
    end
    local o = {}
    setmetatable(o, Class)
    Class.__index = Class
    o:init()
    o.character = player
    o.player = player:getPlayerNum()
    o.item = item
    o.capsuleId = item and item:getID()
    o.mode = mode
    o.joypad = JoypadState.players[o.player + 1] ~= nil
    o.skipBuildAction = true
    o.skipWalk2 = true
    o.noNeedHammer = true
    o.dragNilAfterPlace = true
    return o
end

return Cursor
