-- Vehicle Capsule: server commands of the admin panel (records tab). Every command checks M.isAdmin itself
-- (Capability.ManipulateVehicle, same as Admin.resolve/restore); a refused one is logged and answered NOT_ADMIN.
-- Restore uses the recorded spot, or the square and facing the admin picked with the restore cursor (Admin.restore
-- checks the vehicle's ground there). The two "go to" buttons use the coordinates the detail reply carried (recorded
-- spot, last sighting). The loot and settings tabs need no command: they send sandbox options like the vanilla
-- sandbox page.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Admin"
require "MinidoracatVehicleCapsule/Index"
local M = MinidoracatVehicleCapsule
local Store, Admin, Index = M.Store, M.Admin, M.Index
local AdminCommands = {}
M.AdminCommands = AdminCommands

AdminCommands.HISTORY_MAX = 100 -- newest entries in a detail reply; the file keeps all of them
AdminCommands.NOTE_MAX = 200

local function note(s)
    if type(s) ~= "string" then return nil end
    s = string.gsub(string.gsub(s, "^%s+", ""), "%s+$", "")
    if s == "" then return nil end
    return string.sub(s, 1, AdminCommands.NOTE_MAX)
end

local function flag(v) return v == true or v == "1" end

-- args: q, state, page
function AdminCommands.adminPage(player, args)
    local res = Index.page({ q = args.q, state = args.state }, args.page, Index.PAGE_SIZE)
    res.ok, res.q, res.state, res.seq = true, args.q, args.state, args.seq
    return res
end

-- args: id. Everything the detail pane shows; history is trimmed to the newest HISTORY_MAX entries.
function AdminCommands.adminDetail(player, args)
    local id = tonumber(args.id) or -1
    local snap, why = Store.read(id)
    if not snap then return { ok = false, id = id, why = why } end
    local h = snap.history or {}
    local history = {}
    for i = math.max(1, #h - AdminCommands.HISTORY_MAX + 1), #h do
        local e = h[i]
        history[#history + 1] = { t = e.t, ev = e.ev, by = e.by, x = e.x, y = e.y, z = e.z, car = e.car, why = e.why,
            verdict = e.verdict, note = e.note, items = e.items }
    end
    local manifest = {}
    for ft, n in pairs(snap.manifest or {}) do manifest[#manifest + 1] = { ft = ft, n = n } end
    local e = Store.recordedCar(snap)
    local s = type(snap.seen) == "table" and snap.seen or nil
    return {
        ok = true, id = id, state = snap.state, settled = snap.settled == true, uncertain = Store.uncertain(id, snap),
        script = snap.script, name = snap.name, by = snap.packedBy, history = history, historyTotal = #h,
        manifest = manifest, x = e.x, y = e.y, z = e.z, car = e.car,
        carLoaded = Store.findLoadedVehicle(e.car, snap.script) ~= nil,
        seen = s and { t = s.t, where = s.where, by = s.by, x = s.x, y = s.y, z = s.z } or nil,
    }
end

-- args: id, verdict ("present" / "missing"), note, checked
function AdminCommands.adminResolve(player, args)
    return Admin.resolve(player, tonumber(args.id) or -1, args.verdict, note(args.note), flag(args.checked))
end

local DIRS = { N = true, E = true, S = true, W = true }

-- args: id, note, checked; x, y, z, dir when the admin picked the spot. Without them the vehicle comes back where it
-- was recorded (that square has to be loaded).
function AdminCommands.adminRestore(player, args)
    local id = tonumber(args.id) or -1
    if args.x ~= nil then
        local x, y, z = tonumber(args.x), tonumber(args.y), tonumber(args.z) or 0
        if not (x and y and DIRS[args.dir]) then return { ok = false, why = "BAD_SPOT" } end
        return Admin.restore(player, id, math.floor(x), math.floor(y), math.floor(z), note(args.note), flag(args.checked),
            args.dir)
    end
    local snap = Store.read(id)
    local e = snap and Store.recordedCar(snap) or {}
    return Admin.restore(player, id, tonumber(e.x), tonumber(e.y), tonumber(e.z) or 0, note(args.note), flag(args.checked))
end

-- One entry for MP (OnClientCommand) and SP (the panel calls it directly). Returns the reply table.
function AdminCommands.handle(player, command, args)
    local fn = AdminCommands[command]
    if type(fn) ~= "function" or string.sub(command, 1, 5) ~= "admin" then return nil end
    args = type(args) == "table" and args or {}
    if not M.isAdmin(player) then
        M.log("refused " .. command .. " from non-admin " .. tostring(player and player:getUsername()))
        return { ok = false, why = "NOT_ADMIN", id = args.id }
    end
    local ok, res = pcall(fn, player, args)
    if not ok or type(res) ~= "table" then
        M.log(command .. " failed: " .. tostring(res))
        res = { ok = false, why = "ERROR" }
    end
    res.id = res.id or tonumber(args.id)
    if command ~= "adminPage" then
        M.log(command .. " by " .. player:getUsername() .. " capsule=" .. tostring(args.id) .. " -> ok="
            .. tostring(res.ok) .. " why=" .. tostring(res.why))
    end
    return res
end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= M.MODULE or not player then return end
    local res = AdminCommands.handle(player, command, args)
    if not res then return end
    local ok, err = pcall(sendServerCommand, player, M.MODULE, command, res)
    if not ok then M.log(command .. " reply failed: " .. tostring(err)) end
end)

return AdminCommands
