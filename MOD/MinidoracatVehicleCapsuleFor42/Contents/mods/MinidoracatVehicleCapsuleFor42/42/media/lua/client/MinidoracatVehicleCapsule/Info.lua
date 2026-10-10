-- Vehicle Capsule (client): capsule summaries from the server (server/Query.lua), cached by capsule id, and the
-- wording the tooltip and the preview share. The item only carries its id; nothing here reads item modData.
-- A cached summary is dropped when the server writes that snapshot (queryChanged), so the next hover asks again.
-- Text is built in the player's language from raw data: vehicle and part names from the scripts, not the server.
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Condition"
local M = MinidoracatVehicleCapsule
local Info = {}
M.Info = Info

Info.RETRY_MS = 3000 -- an unanswered request is sent again after this (the server drops requests that come too fast)
Info.CARGO_LINES = 4 -- cargo kinds listed before "N more"
Info.MODS_TIP = 3   -- modification parts named in the tooltip before "N more"
Info.MODS_FULL = 6  -- ... and in the preview list

local cache = {}     -- capsuleId -> reply ({ ok = true, ... } or { ok = false, why })
local asked = {}     -- capsuleId -> ms of the pending request
Info.listeners = {}  -- fn(capsuleId) when a summary arrives or is dropped (the preview window)

local function T(key, a, b, c)
    local k = "Tooltip_MinidoracatVehicleCapsule_" .. key
    if a == nil then return getText(k) end
    if b == nil then return getText(k, a) end
    if c == nil then return getText(k, a, b) end
    return getText(k, a, b, c)
end
Info.T = T

local function notify(id)
    for _, fn in ipairs(Info.listeners) do fn(id) end
end

local function store(reply)
    local id = tonumber(reply.id)
    if not id then return end
    cache[id], asked[id] = reply, nil
    notify(id)
end

-- Forgets a summary (the server wrote that snapshot). Also called directly in SP (server/Query.lua listener).
function Info.drop(id)
    id = tonumber(id)
    if not id then return end
    cache[id], asked[id] = nil, nil
    notify(id)
end
M.QueryChanged = Info.drop

local function request(id)
    local player = getSpecificPlayer(0)
    if not player then return end
    asked[id] = getTimestampMs()
    if isClient() then
        sendClientCommand(player, M.MODULE, "query", { ids = { id } })
    elseif M.Query then -- SP: the server code is loaded in the same Lua state
        for _, r in ipairs(M.Query.query(player, { id }).items) do store(r) end
    end
end

-- The cached reply, or nil while it is being fetched (a request goes out at most every RETRY_MS). In SP the answer
-- is computed in place, so it is returned right away.
function Info.get(id)
    local r = cache[id]
    if r then return r end
    local at = asked[id]
    local now = getTimestampMs()
    if not at or now < at or now - at > Info.RETRY_MS then request(id) end
    return cache[id]
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE or type(args) ~= "table" then return end
    if command == "query" and type(args.items) == "table" then
        for _, r in ipairs(args.items) do
            if type(r) == "table" then store(r) end
        end
    elseif command == "queryChanged" then
        Info.drop(args.id)
    end
end)

-- ---------------------------------------------------------------- wording

-- Same key rule as ISVehicleMenu.getVehicleDisplayName, in this player's language; the snapshot name (server
-- language) only when the vehicle script is gone.
function Info.carName(script, fallback)
    local sc = script and getScriptManager():getVehicle(script)
    if sc then
        local text = getTextOrNull("IGUI_VehicleName" .. (sc:getCarModelName() or sc:getName()))
        if text then return text end
    end
    return fallback or script or "?"
end

function Info.partName(id)
    return getTextOrNull("IGUI_VehiclePart" .. tostring(id)) or tostring(id)
end

function Info.itemName(fullType)
    local item = fullType and getScriptManager():FindItem(fullType)
    return item and item:getDisplayName() or tostring(fullType)
end

-- "10/09 18:40" in local time.
local sdf
function Info.date(ms)
    if type(ms) ~= "number" then return "-" end
    local ok, s = pcall(function()
        sdf = sdf or SimpleDateFormat.new("MM/dd HH:mm", Locale.ENGLISH)
        local cal = Calendar.getInstance()
        cal:setTimeInMillis(ms)
        return sdf:format(cal:getTime())
    end)
    return ok and tostring(s) or "-"
end

local function num1(v)
    local s = string.format("%.1f", v)
    return (string.gsub(s, "%.0$", ""))
end

-- Insertion sort for short lists (cargo kinds, part names); the family gate bans the built-in sort.
local function isort(a, less)
    for i = 2, #a do
        local v, j = a[i], i - 1
        while j >= 1 and less(v, a[j]) do a[j + 1] = a[j]; j = j - 1 end
        a[j + 1] = v
    end
    return a
end
Info.isort = isort

-- Numbers and names for one summary, computed once per reply.
function Info.details(r)
    if r.d then return r.d end
    local c = M.Condition.of(r.parts)
    local d = { engine = c.engine, body = c.body, battery = c.battery, fuel = c.fuel, fuelCap = c.fuelCap,
        missing = {}, mods = {}, cargo = {}, cargoN = 0 }
    for i, id in ipairs(c.missing) do d.missing[i] = Info.partName(id) end
    for i, fullType in ipairs(c.mods) do d.mods[i] = Info.itemName(fullType) end
    local byName = function(a, b) return a < b end
    isort(d.missing, byName)
    isort(d.mods, byName)
    -- Parts can share one item (KI5 left and right window armor): list each name once, with " x2" for repeats.
    local merged = {}
    for _, name in ipairs(d.mods) do
        local last = merged[#merged]
        if last and last.name == name then last.n = last.n + 1 else merged[#merged + 1] = { name = name, n = 1 } end
    end
    d.mods = {}
    for i, m in ipairs(merged) do d.mods[i] = m.n > 1 and (m.name .. " x" .. m.n) or m.name end
    for _, e in ipairs(r.manifest or {}) do
        d.cargo[#d.cargo + 1] = { name = Info.itemName(e.ft), n = tonumber(e.n) or 0 }
        d.cargoN = d.cargoN + (tonumber(e.n) or 0)
    end
    isort(d.cargo, function(a, b)
        if a.n ~= b.n then return a.n > b.n end
        return a.name < b.name
    end)
    r.d = d
    return d
end

local function joinNames(list)
    return table.concat(list, ", ")
end

-- Status text for a capsule that cannot be unpacked (or nil): unpacked, restored, void, crash-uncertain.
function Info.status(r)
    if r.state == "UNPACKED" then return T("Unpacked", Info.date(r.last and r.last.t)) end
    if r.state == "RESTORED" then return T("Restored") end
    if r.state == "VOID" then return T("Void") end
    if r.uncertain then return T("Uncertain") end
    return nil
end

-- { { label, value, token? }, ... } describing the vehicle (PACKED and uncertain ones): what the tooltip and the
-- preview list. `full` adds paint and the whole cargo list (preview).
function Info.rows(r, full)
    local d = Info.details(r)
    local rows = {}
    local function add(label, value, token) rows[#rows + 1] = { T(label), value, token } end
    add("Vehicle", Info.carName(r.script, r.name))
    if full then
        local sc = r.script and getScriptManager():getVehicle(r.script)
        local n = sc and sc:getSkinCount() or 0
        if n > 0 and type(r.skin) == "number" then add("Paint", T("PaintOf", tostring(r.skin + 1), tostring(n))) end
    end
    if d.engine or d.body then
        add("Condition", T("EngineBody", d.engine and tostring(d.engine) or "-", d.body and tostring(d.body) or "-"))
    end
    if d.fuel then
        add("Fuel", d.fuelCap and T("FuelOf", num1(d.fuel), tostring(d.fuelCap)) or T("FuelL", num1(d.fuel)))
    end
    if d.battery then add("Battery", T("Percent", tostring(d.battery))) end
    if #d.missing > 0 then add("Missing", joinNames(d.missing)) end
    if #d.mods > 0 then
        -- KI5 trucks carry a dozen or more extra parts: list a few, count the rest (cargo must stay visible)
        local cap = full and Info.MODS_FULL or Info.MODS_TIP
        if #d.mods <= cap then
            add("Mods", joinNames(d.mods))
        else
            local some = {}
            for i = 1, cap do some[i] = d.mods[i] end
            add("Mods", joinNames(some) .. ", " .. T("CargoMore", tostring(#d.mods - cap)))
        end
    end
    if d.cargoN == 0 then
        add("Cargo", T("CargoNone"))
    else
        add("Cargo", T("CargoCount", tostring(d.cargoN)))
        local shown = full and #d.cargo or math.min(#d.cargo, Info.CARGO_LINES)
        for i = 1, shown do
            local e = d.cargo[i]
            rows[#rows + 1] = { "", T("CargoLine", e.name, tostring(e.n)) }
        end
        if shown < #d.cargo then rows[#rows + 1] = { "", T("CargoMore", tostring(#d.cargo - shown)) } end
    end
    if r.by then add("PackedBy", tostring(r.by)) end
    return rows
end

-- Lines Minidoracat Economy shows under a listed or auctioned capsule (server Trade.view): the vehicle in this
-- player's language and the numbers the tooltip shows.
function Info.viewLines(v)
    local out = {}
    if type(v) ~= "table" then return out end
    local function add(label, value) out[#out + 1] = T("Row", T(label), value) end
    add("Vehicle", Info.carName(v.script, v.name))
    if v.engine or v.body then
        add("Condition", T("EngineBody", v.engine and tostring(v.engine) or "-", v.body and tostring(v.body) or "-"))
    end
    if v.fuel then
        add("Fuel", v.fuelCap and T("FuelOf", num1(v.fuel), tostring(v.fuelCap)) or T("FuelL", num1(v.fuel)))
    end
    if v.battery then add("Battery", T("Percent", tostring(v.battery))) end
    add("Missing", T("MissingCount", tostring(tonumber(v.missing) or 0)))
    local n = tonumber(v.cargo) or 0
    add("Cargo", n > 0 and T("CargoCount", tostring(n)) or T("CargoNone"))
    return out
end

-- Why Economy will not take this capsule now (server Trade.check detail). A cargo item's reason is Economy's own
-- wording for that rule.
function Info.refusalText(d)
    local code = type(d) == "table" and tostring(d.code) or "OTHER"
    if code == "CARGO" then
        local why = tostring(d.why)
        local reason = getTextOrNull("IGUI_MinidoracatEconomy_Market_Reason_" .. why)
            or getTextOrNull("IGUI_MinidoracatEconomy_Market_Reason_not_whitelisted_" .. why) or why
        return getText("IGUI_MinidoracatVehicleCapsule_Trade_CARGO", Info.itemName(d.type), reason)
    end
    if code == "TOO_MANY" then
        return getText("IGUI_MinidoracatVehicleCapsule_Trade_TOO_MANY", tostring(d.n), tostring(d.max))
    end
    return getTextOrNull("IGUI_MinidoracatVehicleCapsule_Trade_" .. code) or getText("IGUI_MinidoracatVehicleCapsule_Trade_OTHER")
end

-- Minidoracat Economy's client facade (MinidoracatEconomy.v1.Client, rev 5 uniqueItemViews) is complete once every
-- client file has loaded. Older Economy keeps loaded capsules off its market: nothing to register.
Events.OnGameStart.Add(function()
    local api = MinidoracatEconomy and MinidoracatEconomy.v1 and MinidoracatEconomy.v1.Client
    local caps = api and api.CAPABILITIES
    if not (type(caps) == "table" and caps.uniqueItemViews == true and type(api.registerItemView) == "function"
        and type(api.registerRefusalText) == "function") then return end
    api.registerItemView(M.ITEM_LOADED, function(view) return Info.viewLines(view) end)
    api.registerRefusalText(M.ITEM_LOADED, function(detail) return Info.refusalText(detail) end)
end)

-- Capsules shown in the inventory and loot windows (a capsule's own container, or a capsule lying in a shown
-- container): their summaries are asked for now. The server counts a capsule asked about from nearby as a sighting
-- (admin panel: last seen), and with cargo take-out on the first take is not refused while the answer is on its way.
Events.OnRefreshInventoryWindowContainers.Add(function(page, state)
    if state ~= "end" then return end
    for _, button in ipairs(page.backpacks or {}) do
        local inv = button.inventory
        local holder = inv and inv:getContainingItem()
        if holder and holder:getFullType() == M.ITEM_LOADED then Info.get(holder:getID()) end
        local items = inv and inv:getItems()
        for i = 0, (items and items:size() or 0) - 1 do
            local it = items:get(i)
            if it:getFullType() == M.ITEM_LOADED then Info.get(it:getID()) end
        end
    end
end)

return Info
