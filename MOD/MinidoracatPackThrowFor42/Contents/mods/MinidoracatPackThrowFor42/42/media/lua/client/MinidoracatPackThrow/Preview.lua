-- Pack & Throw (client): "Preview vehicle" on a loaded capsule's context menu opens a 3D view of the vehicle type
-- and lists the real condition next to it. The scene is the vanilla preview (ISUI3DScene, as in VehicleSpawnControl
-- MVSC_VehicleTab.lua): it draws the type's default look with every optional part, not this vehicle's paint and parts,
-- which the note under the list says. One window, reused; the list follows the cached summary (Info).
require "MinidoracatPackThrow/Core"
require "MinidoracatPackThrow/Info"
require "MinidoracatPackThrow/UIKit"
require "Vehicles/ISUI/ISUI3DScene"
require "ISUI/ISInventoryPaneContextMenu"
local M = MinidoracatPackThrow
local Info, Kit = M.Info, M.UIKit
local Preview = {}
M.Preview = Preview

local function U(key, a, b)
    local k = "UI_MinidoracatPackThrow_" .. key
    if a == nil then return getText(k) end
    if b == nil then return getText(k, a) end
    return getText(k, a, b)
end

-- Context menu entry; needs the framework (the window is a UI.Window). None for a Pal Sphere or any animal record (no
-- 3D view of animals); its summary is already cached by then (the capsule was named from it when its window listed it).
local function onFill(playerNum, context, items)
    for _, item in ipairs(ISInventoryPane.getActualItems(items)) do
        if M.isLoaded(item) and not M.inCapsule(item) then
            local r = Info.get(item:getID())
            if M.typeOf(item).sphere or (r and r.kind == "animal") then return end
            local option = context:addOption(U("Preview"), item:getID(), Preview.open)
            if not Kit.ok then
                option.notAvailable = true
                local tip = ISToolTip:new()
                tip:initialise()
                tip.description = U("NeedFramework")
                option.toolTip = tip
            end
            return
        end
    end
end
Events.OnFillInventoryObjectContextMenu.Add(onFill)

if not Kit.ok then
    function Preview.open() end
    return Preview
end

local UI, COL, FS, FH = Kit.UI, Kit.COL, Kit.FS, Kit.FH
local PAD, GAP = 12, 8
local SCENE_W, SCENE_H, LIST_W = 440, 300, 330
-- Same angles as the vanilla preview (UI3DScene.java:2604-2627); iso = the opening view
Preview.ANGLES = { front = { 0, 0, 0 }, side = { 0, 270, 0 }, top = { 0, 90, 90 }, iso = { 25, 135, 0 } }
local ZOOM = 5

-- A mod part bound to a wheel without a model makes the vanilla preview throw every frame (UI3DScene.java:7375),
-- which blanks every other UI that frame (MVSC_VehicleTab.lua brokenWheelPart). Returns that part id or nil.
local brokenCache = {}
local function brokenWheelPart(full)
    if brokenCache[full] ~= nil then return brokenCache[full] or nil end
    local found = false
    local ok = pcall(function()
        local bv = BaseVehicle.new(getCell())
        bv:setScript(full)
        for i = 0, bv:getPartCount() - 1 do
            local part = bv:getPartByIndex(i)
            local sp = part:getScriptPart()
            if part:getWheelIndex() >= 0 and sp and sp:getModelCount() == 0 then
                found = part:getId()
                return
            end
        end
    end)
    if not ok then found = false end
    brokenCache[full] = found
    return found or nil
end

local Body = ISPanel:derive("MinidoracatPackThrowPreviewBody")

function Body:prerender()
    local w = self.pv
    -- the model may not be loaded on the first setVehicleScript: the scene stays empty until it is set again
    -- (UI3DScene.java:6101-6105, same retry as MVSC)
    if w.resetAt then
        w.resetAt = w.resetAt - 1
        if w.resetAt <= 0 then
            w.resetAt = nil
            if w.shown then w.scene.javaObject:fromLua2("setVehicleScript", "v", w.shown) end
        end
    end
    Kit.theme:fill(self, w.scene:getX(), w.scene:getY(), SCENE_W, SCENE_H, "well")
end

function Body:render()
    local w = self.pv
    local x0 = PAD + SCENE_W + PAD
    local listW = self.width - x0 - PAD
    if not w.shown then
        Kit.text(self, w.sceneMsg or "", PAD + 12, PAD + 12, "textMuted")
    end
    for i, line in ipairs(w.hint) do Kit.text(self, line, PAD, w.hintY + (i - 1) * FH, "textFaint") end
    local y = PAD
    Kit.text(self, w.title or "", x0, y, "text", UIFont.Medium)
    y = y + getTextManager():getFontHeight(UIFont.Medium) + 2
    Kit.text(self, w.subtitle or "", x0, y, "textFaint")
    y = y + FH + GAP
    for _, row in ipairs(w.lines) do
        if y + FH > w.noteY - GAP then break end
        if row[1] ~= "" then Kit.text(self, row[1], x0, y, "textMuted") end
        Kit.text(self, row[2], x0 + w.labelW, y, row[3] or "text")
        y = y + FH + 2
    end
    local ny = w.noteY
    for _, line in ipairs(w.note) do
        Kit.text(self, line, x0, ny, "textFaint")
        ny = ny + FH
    end
end

local Win = {}
Win.__index = Win

function Win.new()
    local self = setmetatable({ lines = {}, labelW = 0 }, Win)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- the hint under the view buttons and the note under the list keep every line: the window grows from the
    -- hint's second line and the note's fourth line on
    self.hint = Kit.wrap(U("PreviewHint"), SCENE_W)
    self.note = Kit.wrap(U("PreviewNote"), LIST_W)
    local bh = PAD + SCENE_H + GAP + (FH + 10) + GAP + FH + PAD + math.max(0, #self.hint - 1, #self.note - 3) * FH
    local width = PAD + SCENE_W + PAD + LIST_W + PAD
    self.win = UI.Window.new({ x = math.floor((sw - width) / 2), y = math.floor((sh - bh) / 2) - 20, width = width,
        height = bh + 40, title = U("PreviewTitle"), theme = Kit.theme, icon = "carPickup",
        onClose = function() Preview.current = nil end })
    local top = self.win:contentTop()
    self.win:setHeight(top + bh)
    local body = Body:new(0, top, width, bh)
    body.background = false
    body.pv = self
    body:initialise()
    self.win:addChild(body)
    self.body = body

    local scene = ISUI3DScene:new(PAD, PAD, SCENE_W, SCENE_H)
    scene:initialise()
    scene:instantiate()
    scene.background = true
    scene.backgroundColor = { r = 0.045, g = 0.045, b = 0.05, a = 1 }
    scene.borderColor = { r = 1, g = 1, b = 1, a = 0.06 }
    body:addChild(scene)
    self.scene = scene
    scene.pv = self
    -- left drag rotates, right drag pans, wheel zooms around the centre, double click resets (MVSC_VehicleTab.lua)
    scene:setView("UserDefined")
    scene.onMouseDown = function(s) s.mouseDown = true; return true end
    scene.onMouseUp = function(s) s.mouseDown = false; return true end
    scene.onMouseUpOutside = scene.onMouseUp
    scene.onRightMouseDown = function(s) s.rightDown = true; return true end
    scene.onRightMouseUp = function(s) s.rightDown = false; return true end
    scene.onRightMouseUpOutside = scene.onRightMouseUp
    scene.onMouseMove = Win.sceneMove
    scene.onMouseMoveOutside = Win.sceneMove
    scene.onMouseWheel = Win.sceneWheel
    scene.onMouseDoubleClick = function(s) s.pv:setAngle(Preview.ANGLES.iso); return true end
    local j = scene.javaObject
    j:fromLua1("setMaxZoom", 20)
    j:fromLua1("setDrawGrid", false)
    j:fromLua1("createVehicle", "v")
    j:fromLua2("setObjectVisible", "v", false)
    self.viewX, self.viewY = 0, 0
    self:setAngle(Preview.ANGLES.iso)

    local by = PAD + SCENE_H + GAP
    local views = { { "ViewFront", "front" }, { "ViewSide", "side" }, { "ViewTop", "top" }, { "ViewReset", "iso" } }
    -- each button fits its title and they share the spare width; titles too long for the row get equal widths
    -- (the framework button cuts its title and shows the rest in a tooltip)
    local need = 0
    for _, v in ipairs(views) do need = need + Kit.measure(U(v[1])) + 20 end
    local spare = math.floor((SCENE_W - GAP * 3 - need) / 4)
    local bx = PAD
    self.buttons = {}
    for i, v in ipairs(views) do
        local bw = spare >= 0 and Kit.measure(U(v[1])) + 20 + spare or math.floor((SCENE_W - GAP * 3) / 4)
        local b = UI.Button.new({ x = bx, y = by, width = bw, height = FH + 10, title = U(v[1]),
            theme = Kit.theme, target = self, onClick = function(target) target:setAngle(Preview.ANGLES[v[2]]) end })
        body:addChild(b)
        self.buttons[i] = b
        bx = bx + bw + GAP
    end
    self.hintY = by + FH + 10 + GAP
    self.noteY = bh - PAD - FH * #self.note
    return self
end

function Win:setAngle(a)
    self.rot = { a[1], a[2], a[3] }
    self.zoom = ZOOM
    local j = self.scene.javaObject
    j:fromLua3("setViewRotation", a[1], a[2], a[3])
    j:fromLua1("setZoom", ZOOM)
    self:pan(self.viewX, self.viewY) -- back to the centre
end

-- dragView(dx, dy): viewX -= dx, viewY -= dy (UI3DScene.java:1052-1058); the engine rounds, so do we
function Win:pan(dx, dy)
    dx, dy = math.floor(dx + 0.5), math.floor(dy + 0.5)
    if dx == 0 and dy == 0 then return end
    self.scene.javaObject:fromLua2("dragView", dx, dy)
    self.viewX, self.viewY = self.viewX - dx, self.viewY - dy
end

function Win.sceneMove(scene, dx, dy)
    local w = scene.pv
    if scene.rightDown then
        w:pan(dx, dy)
        return
    end
    if not scene.mouseDown then return end
    local r = w.rot
    r[2] = (r[2] + dx / 2) % 360
    r[1] = math.max(-89, math.min(89, r[1] + dy / 2))
    scene.javaObject:fromLua3("setViewRotation", r[1], r[2], r[3])
end

-- zoom around the centre and keep the pan: the pan is in zoomed pixels (UI3DScene.java:378-380,2597)
function Win.sceneWheel(scene, del)
    local w = scene.pv
    local z = math.max(1, math.min(20, w.zoom - del))
    if z == w.zoom then return true end
    local r = math.exp((z - w.zoom) * 0.2)
    scene.javaObject:fromLua1("setZoom", z)
    w:pan(w.viewX - w.viewX * r, w.viewY - w.viewY * r)
    w.zoom = z
    return true
end

-- Puts the summary on screen: 3D model of the type (when the script exists and draws safely) and the list.
function Win:show(r)
    local j = self.scene.javaObject
    local script = r and r.ok and r.script
    local sc = script and getScriptManager():getVehicle(script)
    local blocked = sc and brokenWheelPart(script)
    self.shown = (sc and not blocked) and script or nil
    if self.shown then j:fromLua2("setVehicleScript", "v", self.shown) end
    j:fromLua2("setObjectVisible", "v", self.shown ~= nil)
    self.resetAt = self.shown and 30 or nil
    self.sceneMsg = (not r and U("Loading")) or (script and not sc and U("ScriptMissing")) or (blocked and U("CannotDraw"))
        or ""
    local lines
    if not r then
        self.title, self.subtitle, lines = U("Loading"), "", {}
    elseif not r.ok then
        self.title, self.subtitle = U("PreviewTitle"), ""
        lines = { { "", Info.T(r.why == "FAR" and "Far" or "NoRecord"), "errorText" } }
    else
        self.title, self.subtitle = Info.thingName(r), tostring(r.script or "")
        lines = Info.rows(r, true)
        table.remove(lines, 1) -- the vehicle name is the title
        local status = Info.status(r)
        if status then table.insert(lines, 1, { "", status, "errorText" }) end
    end
    local labelW = 0
    for _, row in ipairs(lines) do labelW = math.max(labelW, Kit.measure(row[1])) end
    labelW = labelW > 0 and labelW + GAP or 0
    -- long values (missing parts, mods) continue on the next rows instead of being cut
    local out = {}
    for _, row in ipairs(lines) do
        for i, part in ipairs(Kit.wrap(row[2], LIST_W - labelW)) do
            out[#out + 1] = { i == 1 and row[1] or "", part, row[3] }
        end
    end
    self.lines, self.labelW = out, labelW
end

-- Opens (or re-targets) the window for a capsule id.
function Preview.open(capsuleId)
    local w = Preview.window or Win.new()
    if not Preview.window then
        Preview.window = w
        w.win:addToUIManager()
    end
    Preview.current = capsuleId
    w:setAngle(Preview.ANGLES.iso)
    w:show(Info.get(capsuleId))
    w.win:setVisible(true)
    w.win:bringToTop()
    return w
end

-- New or dropped summary for the capsule on screen: redraw (a dropped one is fetched again right away).
Info.listeners[#Info.listeners + 1] = function(id)
    local w = Preview.window
    if w and Preview.current == id and w.win:getIsVisible() then w:show(Info.get(id)) end
end

return Preview
