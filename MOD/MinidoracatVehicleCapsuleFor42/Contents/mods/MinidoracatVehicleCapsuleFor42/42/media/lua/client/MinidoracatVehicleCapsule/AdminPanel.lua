-- Vehicle Capsule (client): the admin panel, opened from the family Dock (MinidoracatUIFor42 rev 13).
--   Records: search by capsule id or player, state chips (crash-uncertain and "not seen for a week" among them), one
--     page of 50 rows from the server index, and the detail of the selected capsule: timeline, cargo list, last
--     sighting, go to the recorded spot or to the last sighting, restore, and the verdicts "car is there, close" /
--     "car is gone" for records a crash left uncertain.
--     Every action is a server command (server/AdminCommands.lua) checked there; this file only shows replies.
--   Loot: the master switch and the four places with their weights. They are the sandbox options of the vanilla
--     sandbox page and are sent the same way (copy, set, sendToServer; ISServerSandboxOptionsUI.lua:762-771), so the
--     server checks Capability.SandboxOptions; server/Loot.lua rebuilds the loot tables within a second.
-- Entry: Dock (visible for admins, player option "show in the Dock"); without the Dock, the world context menu.
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Info"
require "MinidoracatVehicleCapsule/UIKit"
require "PZAPI/ModOptions"
local M = MinidoracatVehicleCapsule
local Info, Kit = M.Info, M.UIKit
local Panel = {}
M.AdminPanel = Panel

local function U(key, a, b, c)
    local k = "UI_MinidoracatVehicleCapsule_" .. key
    if a == nil then return getText(k) end
    if b == nil then return getText(k, a) end
    if c == nil then return getText(k, a, b) end
    return getText(k, a, b, c)
end
Panel.U = U

-- Client-side gate for showing the entry; the server checks every command again.
function Panel.isAdmin(player)
    if not player then return false end
    if not isClient() then return true end
    local role = player:getRole()
    return role ~= nil and Capability ~= nil and role:hasCapability(Capability.ManipulateVehicle) == true
end

function Panel.canEditSandbox(player)
    if not player then return false end
    if not isClient() then return true end
    local role = player:getRole()
    return role ~= nil and Capability ~= nil and role:hasCapability(Capability.SandboxOptions) == true
end

-- ---------------------------------------------------------------- server link

local COMMANDS = { adminPage = true, adminDetail = true, adminResolve = true, adminRestore = true }

function Panel.send(cmd, args)
    local player = getSpecificPlayer(0)
    if not player then return end
    if isClient() then
        sendClientCommand(player, M.MODULE, cmd, args)
    elseif M.AdminCommands then -- SP: same handler, same reply path
        Panel.onReply(cmd, M.AdminCommands.handle(player, cmd, args) or { ok = false, why = "ERROR" })
    end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or not COMMANDS[command] or type(args) ~= "table" then return end
    Panel.onReply(command, args)
end)

-- ---------------------------------------------------------------- player option and entry

local showDock = true
local docked = false

local function registerOptions()
    local options = PZAPI.ModOptions:getOptions("MinidoracatVehicleCapsule")
    if options == nil then
        options = PZAPI.ModOptions:create("MinidoracatVehicleCapsule", "UI_MinidoracatVehicleCapsule_OptionsTitle")
        options:addTickBox("ShowDock", "UI_MinidoracatVehicleCapsule_OptShowDock", true,
            "UI_MinidoracatVehicleCapsule_OptShowDock_tooltip")
    end
    function options:apply()
        showDock = self:getOption("ShowDock"):getValue() ~= false
        if docked then Kit.UI.Dock.refresh() end
    end
    PZAPI.ModOptions:load()
    showDock = options:getOption("ShowDock"):getValue() ~= false
end
if PZAPI and PZAPI.ModOptions then
    local ok, err = pcall(registerOptions)
    if not ok then M.log("mod options failed: " .. tostring(err)) end
end

if not Kit.ok then
    -- no framework: the entry tells admins why instead of opening half a window
    function Panel.open()
        Kit.notify(nil, U("NeedFramework"))
    end
    function Panel.onReply() end
end

function Panel.toggle()
    local w = Panel.window
    if w and w.win:getIsVisible() then w.win:close() else Panel.open() end
end

local dockIcon = "media/textures/Item_MinidoracatVehicleCapsuleLoaded.png"
docked = Kit.ok and Kit.CAPS.dock == true and Kit.UI.Dock ~= nil and Kit.UI.Dock.register({
    id = "vehiclecapsule", order = 50, icon = dockIcon,
    label = function() return U("PanelTitle") end,
    onClick = function() Panel.toggle() end,
    isAvailable = function() return showDock and Panel.isAdmin(getSpecificPlayer(0)) end,
    isActive = function() local w = Panel.window; return w ~= nil and w.win:getIsVisible() end,
}) == true

-- Without the Dock: admins get the panel from the world context menu.
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, _, test)
    if docked or test or playerNum ~= 0 or not Panel.isAdmin(getSpecificPlayer(0)) then return end
    context:addOption(U("PanelTitle"), nil, function() Panel.open() end)
end)

if not Kit.ok then return Panel end

-- ---------------------------------------------------------------- layout helpers

local UI, COL, FS, FH, theme = Kit.UI, Kit.COL, Kit.FS, Kit.FH, Kit.theme
local text, fit = Kit.text, Kit.fit
local PAD, GAP = 12, 8
local CH = FH + 10 -- control height
Panel.STATES = { "ALL", "PACKED", "UNPACKED", "RESTORED", "VOID", "UNCERTAIN", "UNSEEN" }

-- " · " between fields; a translation key because Lua source stays ASCII (Kahlua truncates other characters).
local SEP
local function sep()
    SEP = SEP or U("Sep")
    return SEP
end

local function stateLabel(state, uncertain)
    local s = U("State_" .. tostring(state))
    if uncertain then s = s .. sep() .. U("State_UNCERTAIN") end
    return s
end
Panel.stateLabel = stateLabel

function Panel.whyText(why)
    return getTextOrNull("UI_MinidoracatVehicleCapsule_Why_" .. tostring(why)) or U("WhyOther", tostring(why))
end

-- "10/09 18:40  Packed, Bob, (10598, 9861, 0)" plus verdict, reason and note when there are any.
function Panel.eventLine(e)
    local s = Info.date(e.t) .. "  " .. (getTextOrNull("UI_MinidoracatVehicleCapsule_Ev_" .. tostring(e.ev)) or tostring(e.ev))
        .. sep() .. tostring(e.by or "-")
    if e.x then s = s .. sep() .. "(" .. tostring(e.x) .. ", " .. tostring(e.y) .. ", " .. tostring(e.z or 0) .. ")" end
    if e.verdict then s = s .. sep() .. U("Verdict_" .. tostring(e.verdict)) end
    if e.why then s = s .. sep() .. tostring(e.why) end
    if e.note then s = s .. sep() .. U("NoteShown", tostring(e.note)) end
    return s
end

local function cargoText(manifest)
    local list = {}
    for _, e in ipairs(manifest or {}) do list[#list + 1] = { name = Info.itemName(e.ft), n = tonumber(e.n) or 0 } end
    Info.isort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
    if #list == 0 then return U("CargoNone") end
    local parts = {}
    for _, e in ipairs(list) do parts[#parts + 1] = Info.T("CargoLine", e.name, tostring(e.n)) end
    return U("CargoList", table.concat(parts, ", "))
end

-- "Last seen: 10/10 18:40 · on Bob (10763, 9775, 0)": where the server last saw the capsule (Store.seen).
local function seenText(s)
    if type(s) ~= "table" then return U("SeenNone") end
    local spot = "(" .. tostring(s.x or "-") .. ", " .. tostring(s.y or "-") .. ", " .. tostring(s.z or 0) .. ")"
    local place
    if s.where == "player" then place = U("SeenPlayer", tostring(s.by or "-"), spot)
    elseif s.where == "container" then place = U("SeenContainer", spot)
    elseif s.where == "vehicle" then place = U("SeenVehicle", spot)
    else place = U("SeenGround", spot) end
    return U("SeenLine", Info.date(s.t), place)
end
Panel.seenText = seenText

-- List cell: one or two lines, strings computed in bind (render does not allocate).
local Cell = ISPanel:derive("MinidoracatVehicleCapsuleCell")
function Cell:render()
    if not self.line1 then return end
    local list = self.list
    if list:isSelected(self.index) then
        theme:fill(self, 0, 0, self.width, self.height, "selected")
    elseif list:isMouseOver() and list:indexAt(list:getMouseX(), list:getMouseY()) == self.index then
        theme:fill(self, 0, 0, self.width, self.height, "hover")
    end
    if self.line2 then
        local mid = math.floor(self.height / 2)
        text(self, self.line1, 8, mid - FH - 1, self.token1 or "text")
        text(self, self.line2, 8, mid + 1, self.token2 or "textMuted")
    else
        text(self, self.line1, 8, math.floor((self.height - FH) / 2), self.token1 or "text")
    end
end

local function newList(parent, x, y, w, h, twoLines, bind, onSelect)
    local list = UI.VirtualList.new({ x = x, y = y, width = w, height = h, rowHeight = twoLines and FH * 2 + 10 or FH + 6,
        padding = 2,
        createCell = function(l)
            local c = Cell:new(0, 0, 0, 0)
            c.background = false
            c.list = l
            return c
        end,
        bindCell = function(_, c, row, index)
            c.index = index
            bind(c, row, c.width - 16)
        end,
        unbindCell = function(_, c) c.line1, c.line2 = nil, nil end,
        onSelect = onSelect,
        colors = { thumb = COL.textFaint, thumbHover = COL.textMuted, track = COL.hover } })
    list:initialise()
    parent:addChild(list)
    return list
end

local Pane = ISPanel:derive("MinidoracatVehicleCapsulePane")
function Pane:prerender()
    if self.drawBack then self.drawBack(self) end
end
function Pane:render()
    if self.draw then self.draw(self) end
end
local function newPane(parent, x, y, w, h)
    local p = Pane:new(x, y, w, h)
    p.background = false
    p:initialise()
    parent:addChild(p)
    return p
end

-- ---------------------------------------------------------------- window

local Win = {}
Win.__index = Win

function Win.new()
    local self = setmetatable({ q = "", state = "ALL", page = 1, pages = 1, total = 0, counts = {}, rows = {} }, Win)
    local sw, sh = getCore():getScreenWidth(), getCore():getScreenHeight()
    -- 720 high: with a larger font (e.g. a font mod) and the detail buttons on two rows, 640 left the timeline at
    -- its minimum and the status line one row (French, 2026-10-10)
    local w, h = math.min(980, sw - 40), math.min(720, sh - 40)
    self.w, self.h = w, h
    self.win = UI.Window.new({ x = math.floor((sw - w) / 2), y = math.floor((sh - h) / 2), width = w, height = h,
        title = U("PanelTitle"), theme = theme, icon = "carPickup", onClose = function() end })
    local top = self.win:contentTop() + GAP
    self.tabs = UI.Tabs.new({ x = PAD, y = top, items = { { id = "records", label = U("TabRecords") },
        { id = "loot", label = U("TabLoot") } }, selected = "records", theme = theme, target = self,
        onSelect = function(target, id) target:showTab(id) end })
    self.win:addChild(self.tabs)
    local py = top + self.tabs.height + GAP
    self.records = newPane(self.win, 0, py, w, h - py)
    self.loot = newPane(self.win, 0, py, w, h - py)
    self:buildRecords(self.records)
    self:buildLoot(self.loot)
    self:showTab("records")
    return self
end

function Win:showTab(id)
    self.tab = id
    self.records:setVisible(id == "records")
    self.loot:setVisible(id == "loot")
    if id == "loot" then self:loadLoot() end
end

-- ------------------------------------------------ records tab

function Win:buildRecords(p)
    local w = p.width
    local x, y = PAD, 0
    -- the field fits its (translated) hint; the button sits right after it
    local go = UI.Button.new({ y = y, height = CH, title = U("Search"), style = "primary",
        theme = theme, target = self, onClick = function(t) t:runSearch() end })
    local sw = math.min(math.max(300, Kit.measure(U("SearchHint")) + 40), w - PAD * 2 - GAP - go.width)
    self.search = UI.TextField.new({ x = x, y = y, width = sw, height = CH, placeholder = U("SearchHint"),
        theme = theme, clearButton = true })
    p:addChild(self.search)
    go:setX(x + sw + GAP)
    p:addChild(go)
    y = y + CH + GAP
    self.chips = {}
    self.chipY = y
    for i, st in ipairs(Panel.STATES) do
        local b = UI.Button.new({ x = x, y = y, height = CH, title = U("Chip_" .. st, "9999"), style = "chip",
            active = st == self.state, theme = theme, target = self, onClick = function(t) t:setStateFilter(st) end })
        p:addChild(b)
        self.chips[i] = b
    end
    -- the chips flow into as many rows as four-digit counts would need (longer translations wrap), reserved once
    self.chipRows = Kit.flow(self.chips, w - PAD * 2, 6)
    for i, st in ipairs(Panel.STATES) do self.chips[i]:setTitle(U("Chip_" .. st, "0")) end
    self:layoutChips()
    y = y + self.chipRows * (CH + GAP)
    local listW = math.floor((w - PAD * 3) * 0.42)
    local listH = p.height - y - CH - GAP - PAD
    self.listY, self.listW, self.listH = y, listW, listH
    self.list = newList(p, x, y, listW, listH, true, function(c, row, cw) self:bindRow(c, row, cw) end,
        function() self:onPick() end)
    local py = y + listH + GAP
    local function pagerW(key) return math.max(90, Kit.measure(U(key)) + 20) end
    self.prevBtn = UI.Button.new({ x = x, y = py, width = pagerW("PrevPage"), height = CH, title = U("PrevPage"),
        theme = theme, target = self, onClick = function(t) t:goPage(t.page - 1) end })
    self.nextBtn = UI.Button.new({ x = x + listW - pagerW("NextPage"), y = py, width = pagerW("NextPage"), height = CH,
        title = U("NextPage"), theme = theme, target = self, onClick = function(t) t:goPage(t.page + 1) end })
    p:addChild(self.prevBtn)
    p:addChild(self.nextBtn)
    self.pagerY = py

    -- detail column
    local dx = x + listW + PAD
    local dw = w - dx - PAD
    self.dx, self.dw = dx, dw
    local dy = y
    self.headY = dy                                    -- title, state (two lines: the crash help is long)
    dy = dy + getTextManager():getFontHeight(UIFont.Medium) + FH * 2 + GAP
    self.infoY = dy                                    -- recorded spot; car; last sighting
    dy = dy + FH * 3 + GAP
    self.timelineHeadY = dy
    dy = dy + FH + 4
    -- action buttons size to their (translated) titles and flow into as many rows as the column needs; the
    -- timeline gives up that height. Added to the pane below, in the original order.
    local function btn(key, style, fn)
        return UI.Button.new({ height = CH, title = U(key), style = style, theme = theme, target = self, onClick = fn })
    end
    self.gotoBtn = btn("GoTo", "normal", function(t) t:goTo() end)
    self.seenBtn = btn("GoSeen", "normal", function(t) t:goSeen() end)
    self.restoreBtn = btn("Restore", "primary", function(t) t:confirmRestore() end)
    self.presentBtn = btn("VerdictPresent", "normal", function(t) t:resolve("present") end)
    self.missingBtn = btn("VerdictMissing", "danger", function(t) t:resolve("missing") end)
    local actions = { self.gotoBtn, self.seenBtn, self.restoreBtn, self.presentBtn, self.missingBtn }
    local btnRows = Kit.flow(actions, dw, GAP)
    local bottomBlock = (FH + 2) * 2 + GAP + CH + GAP + CH + GAP + btnRows * (CH + GAP) + FH
    local tlH = math.max(FH * 4, listH - (dy - y) - bottomBlock)
    self.whyRows = math.max(1, math.floor((dy - self.headY) / FH)) -- a refused detail shows its reason above the timeline
    self.timeline = newList(p, dx, dy, dw, tlH, false, function(c, row, cw)
        c.line1 = fit(Panel.eventLine(row), cw)
        c.token1 = (row.ev == "REJECTED" or row.ev == "RESTORE_FAILED" or row.ev == "UNPACK_FAILED") and "errorText" or "text"
    end)
    dy = dy + tlH + GAP
    self.cargoY = dy
    dy = dy + (FH + 2) * 2 + GAP
    self.note = UI.TextField.new({ x = dx, y = dy, width = dw, height = CH, placeholder = U("NoteHint"), theme = theme,
        maxLength = 200 })
    p:addChild(self.note)
    dy = dy + CH + GAP
    self.checked = UI.Checkbox.new({ x = dx, y = dy, width = dw, label = U("CheckedSite"), theme = theme })
    p:addChild(self.checked)
    dy = dy + CH + GAP
    for _, b in ipairs(actions) do
        b:setX(dx + b.flowX)
        b:setY(dy + b.flowRow * (CH + GAP))
        p:addChild(b)
    end
    dy = dy + btnRows * (CH + GAP)
    self.msgY = dy
    self.msgRows = math.max(1, math.floor((p.height - PAD - dy) / FH))
    p.drawBack = function(el)
        theme:fill(el, PAD, self.listY, self.listW, self.listH, "well")
        theme:fill(el, self.dx, self.timeline:getY(), self.dw, self.timeline.height, "well")
    end
    p.draw = function(el) self:drawRecords(el) end
    self:refreshButtons()
end

function Win:layoutChips()
    Kit.flow(self.chips, self.records.width - PAD * 2, 6)
    for _, b in ipairs(self.chips) do
        b:setX(PAD + b.flowX)
        b:setY(self.chipY + math.min(b.flowRow, self.chipRows - 1) * (CH + GAP))
    end
end

function Win:bindRow(c, row, cw)
    c.line1 = fit(tostring(row.id) .. "   " .. Info.carName(row.script, row.name), cw)
    c.line2 = fit(tostring(row.by or "-") .. sep() .. Info.date(row.t) .. sep() .. stateLabel(row.state, row.uncertain), cw)
    c.token1 = "text"
    c.token2 = row.uncertain and "errorText" or "textMuted"
end

function Win:drawRecords(el)
    local px = PAD + math.floor(self.listW / 2)
    local pager = U("PageOf", tostring(self.page), tostring(self.pages), tostring(self.total))
    text(el, pager, px - math.floor(Kit.measure(pager) / 2), self.pagerY + 5, "textMuted")
    if #self.rows == 0 then
        text(el, self.loading and U("Loading") or U("NoRecords"), PAD + 8, self.listY + 8, "textFaint")
    end
    local d = self.detail
    local x = self.dx
    if not d then
        text(el, self.pickedId and U("Loading") or U("PickRecord"), x, self.headY, "textFaint")
    elseif not d.ok then
        for i, line in ipairs(self.dWhy) do text(el, line, x, self.headY + (i - 1) * FH, "errorText") end
    else
        text(el, self.dTitle, x, self.headY, "text", UIFont.Medium)
        local sy = self.headY + getTextManager():getFontHeight(UIFont.Medium)
        local token = d.uncertain and "errorText" or "accent"
        for i, line in ipairs(self.dState) do text(el, line, x, sy + (i - 1) * FH, token) end
        for i, line in ipairs(self.dInfo) do text(el, line, x, self.infoY + (i - 1) * FH, "textMuted") end
        text(el, self.dTimelineHead, x, self.timelineHeadY, "textMuted")
        for i, line in ipairs(self.dCargo) do
            text(el, line, x, self.cargoY + (i - 1) * (FH + 2), "text")
        end
    end
    if self.msgLines then
        for i, line in ipairs(self.msgLines) do text(el, line, x, self.msgY + (i - 1) * FH, self.msgToken) end
    end
end

function Win:refreshButtons()
    local d = self.detail
    local ok = d ~= nil and d.ok == true and not self.busy
    local restorable = ok and (d.state == "PACKED" or (d.state == "UNPACKED" and d.uncertain))
    local undecided = ok and d.uncertain and (d.state == "PACKED" or d.state == "UNPACKED")
    self.gotoBtn:setEnabled(ok and d.x ~= nil)
    self.seenBtn:setEnabled(ok and type(d.seen) == "table" and d.seen.x ~= nil)
    self.restoreBtn:setEnabled(restorable == true)
    self.presentBtn:setVisible(undecided == true)
    self.missingBtn:setVisible(undecided == true)
    self.prevBtn:setEnabled(self.page > 1 and not self.loading)
    self.nextBtn:setEnabled(self.page < self.pages and not self.loading)
end

-- Every request carries a sequence number; a reply to an older request (the admin clicked on) is dropped.
function Win:requestPage()
    self.loading = true
    self.seq = (self.seq or 0) + 1
    self:refreshButtons()
    Panel.send("adminPage", { q = self.q, state = self.state, page = self.page, seq = self.seq })
end

function Win:runSearch()
    self.q = self.search:getText() or ""
    self.page = 1
    self:requestPage()
end

function Win:setStateFilter(st)
    self.state = st
    for i, b in ipairs(self.chips) do b:setActive(Panel.STATES[i] == st) end
    self.page = 1
    self:requestPage()
end

-- Status line under the buttons: wrapped to the detail column, as many rows as fit above the pane's bottom.
function Win:setMsg(s, token)
    self.msg, self.msgToken = s, token
    self.msgLines = s and Kit.lines(s, self.dw, self.msgRows) or nil
end

function Win:goPage(n)
    if n < 1 or n > self.pages then return end
    self.page = n
    self:requestPage()
end

function Win:onPage(res)
    if res.seq ~= nil and res.seq ~= self.seq then return end
    self.loading = false
    if not res.ok then
        self:setMsg(Panel.whyText(res.why), "errorText")
        self:refreshButtons()
        return
    end
    self.rows = type(res.rows) == "table" and res.rows or {}
    self.page, self.pages, self.total = tonumber(res.page) or 1, tonumber(res.pages) or 1, tonumber(res.total) or 0
    self.counts = type(res.counts) == "table" and res.counts or {}
    for i, st in ipairs(Panel.STATES) do self.chips[i]:setTitle(U("Chip_" .. st, tostring(self.counts[st] or 0))) end
    self:layoutChips()
    self.list:setItems(self.rows)
    -- keep the selection when the picked capsule is still on this page
    for i, row in ipairs(self.rows) do
        if row.id == self.pickedId then self.list:setSelectedIndex(i) end
    end
    self:refreshButtons()
end

function Win:onPick()
    local row = self.list:getSelectedItem()
    if not row or row.id == self.pickedId then return end
    self:select(row.id)
end

function Win:select(id)
    self.pickedId, self.detail = id, nil
    self:setMsg(nil)
    self.timeline:setItems({})
    self.note:setText("")
    self.checked:setChecked(false, true)
    self:refreshButtons()
    Panel.send("adminDetail", { id = id })
end

function Win:onDetail(d)
    if tonumber(d.id) ~= self.pickedId then return end
    self.detail = d
    if not d.ok then
        self.dWhy = Kit.lines(Panel.whyText(d.why), self.dw, self.whyRows)
    else
        self.dTitle = fit(tostring(d.id) .. "   " .. Info.carName(d.script, d.name), self.dw)
        self.dState = Kit.lines(stateLabel(d.state, d.uncertain) .. (d.uncertain and ("  " .. U("UncertainHelp")) or ""),
            self.dw, 2)
        local spot = d.x and U("Spot", tostring(d.x), tostring(d.y), tostring(d.z or 0)) or U("SpotNone")
        local car = U(d.carLoaded and "CarLoaded" or "CarNotLoaded", tostring(d.car or "-"))
        self.dInfo = { fit(spot, self.dw), fit(car, self.dw), fit(seenText(d.seen), self.dw) }
        local more = (tonumber(d.historyTotal) or 0) - #(d.history or {})
        self.dTimelineHead = more > 0 and U("TimelineMore", tostring(more)) or U("Timeline")
        self.dCargo = Kit.lines(cargoText(d.manifest), self.dw, 2)
        local h = {}
        for i = #(d.history or {}), 1, -1 do h[#h + 1] = d.history[i] end -- newest first
        self.timeline:setItems(h)
    end
    self:refreshButtons()
end

function Win:goTo()
    local d, player = self.detail, getSpecificPlayer(0)
    if not (d and d.x and player) then return end
    -- a few tiles beside the spot: a restored vehicle spawns on it facing north. Same path as the vanilla admin
    -- tools (ISSafehousesList.lua:98-102): the server command in MP, a direct teleport in SP.
    local x, y, z = d.x + 4, d.y, d.z or 0
    if isClient() then
        SendCommandToServer("/teleportto " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
    else
        player:teleportTo(x, y, z)
    end
    self:setMsg(U("WentTo", tostring(d.x), tostring(d.y)), "accent")
end

-- The square where the capsule was last seen: an admin checks whether it is still there (a player says it is lost).
function Win:goSeen()
    local d, player = self.detail, getSpecificPlayer(0)
    local s = d and d.seen
    if not (type(s) == "table" and s.x and player) then return end
    local x, y, z = s.x, s.y, s.z or 0
    if isClient() then
        SendCommandToServer("/teleportto " .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z))
    else
        player:teleportTo(x, y, z)
    end
    self:setMsg(U("WentToSeen", tostring(x), tostring(y)), "accent")
end

local function noteText(field)
    local s = field:getText() or ""
    s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
    return s
end

function Win:act(cmd, args)
    self.busy = true
    self:setMsg(U("Sending"), "textMuted")
    self:refreshButtons()
    Panel.send(cmd, args)
end

function Win:confirmRestore()
    local d = self.detail
    if not d then return end
    local args = { id = d.id, note = noteText(self.note), checked = self.checked:getChecked() }
    if not (Kit.CAPS.dialog and UI.Dialog) then return self:act("adminRestore", args) end
    self.dialog = UI.Dialog.show({ title = U("Restore"), text = U("RestoreConfirm", Info.carName(d.script, d.name),
        tostring(d.x), tostring(d.y)), theme = theme, confirmText = U("Restore"), cancelText = U("Cancel"),
        onResult = function(ok)
            self.dialog = nil
            if ok then self:act("adminRestore", args) end
        end })
end

function Win:resolve(verdict)
    local d = self.detail
    if not d then return end
    self:act("adminResolve", { id = d.id, verdict = verdict, note = noteText(self.note), checked = self.checked:getChecked() })
end

function Win:onAction(cmd, res)
    self.busy = false
    if res.ok then
        self:setMsg(U(cmd == "adminRestore" and "Restored" or "Resolved"), "accent")
        Kit.notify(U("PanelTitle"), self.msg)
    else
        self:setMsg(Panel.whyText(res.why), "errorText")
    end
    self:refreshButtons()
    self:requestPage()
    if self.pickedId then Panel.send("adminDetail", { id = self.pickedId }) end
end

-- ------------------------------------------------ loot tab

Panel.PLACES = {
    { "LootMechanic", "LootMechanicWeight" },
    { "LootCarSupply", "LootCarSupplyWeight" },
    { "LootGasStation", "LootGasStationWeight" },
    { "LootGarage", "LootGarageWeight" },
}

local function option(key)
    local opts = getSandboxOptions()
    local o = opts and opts:getOptionByName("MinidoracatVehicleCapsule." .. key)
    return o and o:getValue()
end

local function fmtWeight(v) return string.format("%.1f", v) end

function Win:buildLoot(p)
    local w = p.width
    local y = 0
    self.lootRows = {}
    self.master = UI.Checkbox.new({ x = PAD, y = y, width = w - PAD * 2, label = getText("Sandbox_MinidoracatVehicleCapsule_LootEnabled"),
        theme = theme, target = self, onChange = function(t) t:lootChanged() end })
    p:addChild(self.master)
    y = y + CH + GAP * 2
    local sliderW = 260
    for i, pl in ipairs(Panel.PLACES) do
        local box = UI.Checkbox.new({ x = PAD + 16, y = y, width = w - PAD * 2 - sliderW - 40,
            label = getText("Sandbox_MinidoracatVehicleCapsule_" .. pl[1]), theme = theme, target = self,
            onChange = function(t) t:lootChanged() end })
        local slider = UI.Slider.new({ x = w - PAD - sliderW, y = y, width = sliderW, min = 0, max = 10, step = 0.1,
            value = 0, theme = theme, format = fmtWeight, target = self, onChange = function(t) t:lootChanged() end })
        p:addChild(box)
        p:addChild(slider)
        self.lootRows[i] = { box = box, slider = slider, y = y,
            tables = getText("Sandbox_MinidoracatVehicleCapsule_" .. pl[1] .. "_tooltip") }
        y = y + CH + FH + GAP
    end
    self.lootNoteY = y
    y = y + FH * 2 + GAP
    self.lootDiscard = UI.Button.new({ x = PAD, y = y, height = CH, title = U("Discard"), theme = theme, target = self,
        onClick = function(t) t:loadLoot() end })
    self.lootApply = UI.Button.new({ x = PAD + self.lootDiscard.width + GAP, y = y, height = CH, title = U("Apply"),
        style = "primary", theme = theme, target = self, onClick = function(t) t:applyLoot() end })
    p:addChild(self.lootDiscard)
    p:addChild(self.lootApply)
    self.lootMsgY = y + CH + GAP
    p.draw = function(el)
        for _, r in ipairs(self.lootRows) do
            text(el, fit(r.tables, el.width - PAD * 2 - 60), PAD + 56, r.y + CH, "textFaint")
        end
        local ny = self.lootNoteY
        for _, line in ipairs(self.lootNote or {}) do
            text(el, line, PAD, ny, "textMuted")
            ny = ny + FH
        end
        if self.lootMsg then text(el, self.lootMsg, PAD, self.lootMsgY, self.lootMsgToken or "accent") end
    end
    self.lootNote = Kit.wrap(U("LootNote"), w - PAD * 2)
end

-- Values the dialog started from (current native options) into the controls.
function Win:loadLoot()
    self.lootBase = { LootEnabled = option("LootEnabled") ~= false }
    self.master:setChecked(self.lootBase.LootEnabled, true)
    for i, pl in ipairs(Panel.PLACES) do
        local on, wt = option(pl[1]) ~= false, tonumber(option(pl[2])) or 0
        self.lootBase[pl[1]], self.lootBase[pl[2]] = on, wt
        self.lootRows[i].box:setChecked(on, true)
        self.lootRows[i].slider:setValue(wt, true)
    end
    self.lootMsg = nil
    self:lootChanged()
end

function Win:lootDraft()
    local d = { LootEnabled = self.master:getChecked() }
    for i, pl in ipairs(Panel.PLACES) do
        d[pl[1]] = self.lootRows[i].box:getChecked()
        d[pl[2]] = self.lootRows[i].slider:getValue()
    end
    return d
end

-- Changes against the base: { { key, value } }. Weights compare at one decimal (the slider step).
function Win:lootChanges()
    local d, out = self:lootDraft(), {}
    for k, v in pairs(d) do
        local b = self.lootBase and self.lootBase[k]
        local differ = type(v) == "number" and math.abs(v - (tonumber(b) or 0)) > 0.05 or (type(v) ~= "number" and v ~= b)
        if differ then out[#out + 1] = { k, v } end
    end
    return out
end

function Win:lootChanged()
    local allowed = Panel.canEditSandbox(getSpecificPlayer(0))
    local n = #self:lootChanges()
    local on = self.master:getChecked()
    for _, r in ipairs(self.lootRows) do
        r.box:setEnabled(on and allowed)
        r.slider:setEnabled(on and allowed and r.box:getChecked())
    end
    self.master:setEnabled(allowed)
    self.lootApply:setEnabled(allowed and n > 0)
    self.lootDiscard:setEnabled(n > 0)
    if not allowed then self.lootMsg, self.lootMsgToken = U("NoSandboxRight"), "errorText" end
end

-- Same path as the vanilla sandbox page: MP sends a full copy (the server checks Capability.SandboxOptions, saves
-- and broadcasts it); SP sets the native options and refreshes SandboxVars.
function Panel.applySandbox(changes)
    if #changes == 0 then return end
    if isClient() then
        local copy = SandboxOptions.new()
        copy:copyValuesFrom(getSandboxOptions())
        for _, c in ipairs(changes) do copy:set("MinidoracatVehicleCapsule." .. c[1], c[2]) end
        copy:sendToServer()
    else
        local opts = getSandboxOptions()
        for _, c in ipairs(changes) do opts:set("MinidoracatVehicleCapsule." .. c[1], c[2]) end
        opts:toLua()
    end
end

function Win:applyLoot()
    local changes = self:lootChanges()
    if #changes == 0 or not Panel.canEditSandbox(getSpecificPlayer(0)) then return end
    Panel.applySandbox(changes)
    self.lootBase = self:lootDraft()
    self.lootMsg, self.lootMsgToken = U("LootApplied", tostring(#changes)), "accent"
    self:lootChanged()
end

-- ---------------------------------------------------------------- entry points

function Panel.open()
    local player = getSpecificPlayer(0)
    if not Panel.isAdmin(player) then
        Kit.notify(U("PanelTitle"), Panel.whyText("NOT_ADMIN"))
        return
    end
    local w = Panel.window
    if not w then
        w = Win.new()
        Panel.window = w
        w.win:addToUIManager()
    end
    w.win:setVisible(true)
    w.win:bringToTop()
    if w.tab == "loot" then w:loadLoot() end
    w:requestPage()
    return w
end

function Panel.onReply(cmd, res)
    local w = Panel.window
    if not w then return end
    if cmd == "adminPage" then
        w:onPage(res)
    elseif cmd == "adminDetail" then
        w:onDetail(res)
    else
        w:onAction(cmd, res)
    end
end

return Panel
