-- Pack & Throw (client): what is inside a capsule, under the item tooltip. Same stacking as MiniMapWatch
-- Hud.lua and ItemCleaner Tooltip.lua: the wrapper is installed in OnGameStart (outermost), lets everything below
-- draw first, measures how far it drew and adds one box under it. Nothing is written in render: the summary comes
-- from Info (requested once, cached), the lines are built once per summary.
require "MinidoracatPackThrow/Core"
require "MinidoracatPackThrow/Rules"
require "MinidoracatPackThrow/Info"
require "ISUI/ISToolTipInv"
local M = MinidoracatPackThrow
local Info = M.Info
local T = Info.T
local Tooltip = {}
M.Tooltip = Tooltip

local PAD, GAP = 5, 10
local MIN_W = 380 -- with wrapping, the box is at least this wide and continuation rows wrap to it
local loading, empties -- built on first use (translations are ready by then); empties: "<type id><0|1>" -> rows

-- The framework's line breaker (MinidoracatUI Text.wrap, rev 16: CJK, French punctuation, cached per font, width and
-- text, so calling it every frame allocates nothing), or nil on a framework without it: then rows stay one line and
-- the box widens to the longest, as before.
local function wrapper()
    local UI = MinidoracatUI and MinidoracatUI.v1
    if UI and UI.CAPABILITIES and UI.CAPABILITIES.textWrap and UI.Text and type(UI.Text.wrap) == "function" then
        return UI.Text.wrap
    end
    return nil
end

local function ownSlots(self)
    local rect, border
    for k, v in pairs(self) do
        if k == "drawRect" then rect = v elseif k == "drawRectBorder" then border = v end
    end
    return rect, border
end

-- Runs the original render while recording the lowest rectangle it draws (the vanilla box, or whatever a mod
-- below drew outside it). nil = nothing drawn this frame (vanilla skips while a context menu is open).
local function renderMeasured(self, original)
    local ownRect, ownBorder = ownSlots(self)
    local fwdRect, fwdBorder = self.drawRect, self.drawRectBorder
    local bottom
    local function track(y, w, h)
        if w > 0 and h > 0 and (not bottom or y + h > bottom) then bottom = y + h end
    end
    rawset(self, "drawRect", function(ui, x, y, w, h, a, r, g, b)
        track(y, w, h)
        return fwdRect(ui, x, y, w, h, a, r, g, b)
    end)
    rawset(self, "drawRectBorder", function(ui, x, y, w, h, a, r, g, b)
        track(y, w, h)
        return fwdBorder(ui, x, y, w, h, a, r, g, b)
    end)
    local ok, err, trace = pcall(original, self)
    rawset(self, "drawRect", ownRect)
    rawset(self, "drawRectBorder", ownBorder)
    if not ok then error(err, trace) end
    return bottom
end

-- rows = { { label, value, token? } }; a row with an empty label continues the one above (cargo list, notes) and
-- wraps to the box width. Below the vanilla box; above it when the screen ends, not at all when neither fits.
local function appendBox(self, rows, bottom)
    local tm = getTextManager()
    local font = self.tooltip:getFont()
    local lineH = tm:getFontHeight(font)
    local wrap = wrapper()
    local labelW = 0
    for _, row in ipairs(rows) do labelW = math.max(labelW, tm:MeasureStringX(font, row[1])) end
    local valueX = PAD + labelW + (labelW > 0 and GAP or 0)
    local w = math.max(self.width, wrap and MIN_W or 0)
    for _, row in ipairs(rows) do
        if row[1] ~= "" or not wrap then w = math.max(w, valueX + tm:MeasureStringX(font, row[2]) + PAD) end
    end
    local textW = w - valueX - PAD
    local n = 0
    for _, row in ipairs(rows) do n = n + ((wrap and row[1] == "") and #wrap(row[2], textW, font) or 1) end
    local h = PAD * 2 + lineH * n
    local y = bottom - 1
    if self.y + y + h > getCore():getScreenHeight() then
        if self.y - h < 0 then return end
        y = -h + 1
    end
    local bg, bd = self.backgroundColor, self.borderColor
    self:drawRect(0, y, w, h, math.min(1, bg.a + 0.4), bg.r, bg.g, bg.b)
    self:drawRectBorder(0, y, w, h, bd.a, bd.r, bd.g, bd.b)
    local ty = y + PAD
    for _, row in ipairs(rows) do
        local r, g, b = 0.95, 0.95, 0.95
        if row[3] == "warn" then r, g, b = 1, 0.65, 0.3 elseif row[3] == "muted" then r, g, b = 0.65, 0.65, 0.65 end
        if wrap and row[1] == "" then
            for _, line in ipairs(wrap(row[2], textW, font)) do
                self:drawText(line, valueX, ty, r, g, b, 1, font)
                ty = ty + lineH
            end
        else
            if row[1] ~= "" then self:drawText(row[1], PAD, ty, 0.65, 0.65, 0.65, 1, font) end
            self:drawText(row[2], valueX, ty, r, g, b, 1, font)
            ty = ty + lineH
        end
    end
end

-- The note every Pal Sphere carries (user 2026-10-16): time stands still inside (Animal.restore writes the snapshot
-- back without simulating the time away).
local function sphereNote() return { "", T("SphereTime"), "muted" } end

-- The "Type" row: the type's look and sounds in words, so the type never shows by colour alone.
local function typeRow(t)
    return { T("Type"), T("Look_" .. t.id) }
end

-- Rows for a capsule item, or nil for any other item. Built once per summary (empty capsules: per type and switch)
-- and kept.
function Tooltip.rows(item)
    if not item or not item.getFullType then return nil end -- ISToolTipInv also shows energy and fluid bars
    local t = M.typeOf(item)
    if not t then return nil end
    if M.isEmpty(item) then
        local on = M.Rules.typeOn(t)
        local key = t.id .. (on and "1" or "0")
        empties = empties or {}
        if not empties[key] then
            local rows = { typeRow(t), { "", T(t.sphere and "EmptySphere" or "Empty"), "muted" } }
            if not on then rows[#rows + 1] = { "", T("TypeOff"), "warn" } end -- the text starts with a "!" mark
            if t.sphere then rows[#rows + 1] = sphereNote() end
            empties[key] = rows
        end
        return empties[key]
    end
    local r = Info.get(item:getID())
    if not r then
        loading = loading or { { "", T("Loading"), "muted" } }
        return loading
    end
    if r.tipRows then return r.tipRows end
    local rows
    if not r.ok then
        rows = { { "", T(r.why == "FAR" and "Far" or "NoRecord"), "warn" } }
    else
        local status = Info.status(r)
        local animal = r.kind == "animal"
        if status and r.state ~= "PACKED" then
            rows = { typeRow(t), { T(animal and "Animal" or "Vehicle"), Info.thingName(r) }, { "", status, "warn" } }
        else
            rows = Info.rows(r, false)
            table.insert(rows, 1, typeRow(t))
            if status then rows[#rows + 1] = { "", status, "warn" } end
            if not animal then rows[#rows + 1] = { "", T("PreviewHint"), "muted" } end -- no 3D preview of animals
            if t.sphere then rows[#rows + 1] = sphereNote() end
        end
    end
    r.tipRows = rows
    return rows
end

function Tooltip.install()
    if Tooltip.installed or not ISToolTipInv then return end
    Tooltip.installed = true
    local original = ISToolTipInv.render
    function ISToolTipInv:render()
        local rows = Tooltip.rows(self.item)
        if not rows then return original(self) end
        local bottom = renderMeasured(self, original)
        if bottom then appendBox(self, rows, bottom) end
    end
end
Events.OnGameStart.Add(Tooltip.install)

return Tooltip
