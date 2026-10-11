-- Vehicle Capsule: admin API (server). Resolve records a crash left uncertain, and restore a lost vehicle.
-- Callers: the debug commands now (Commands.lua), the admin panel later. Every entry checks M.isAdmin itself.
-- Results are { ok = true, state } or { ok = false, why }.
if isClient() then return end
require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Unpack"
require "MinidoracatVehicleCapsule/Footprint"
local M = MinidoracatVehicleCapsule
local Store, Unpack = M.Store, M.Unpack
local Admin = {}
M.Admin = Admin

local function manifest(snap)
    local parts = {}
    for ft, n in pairs(snap.manifest or {}) do parts[#parts + 1] = ft .. "*" .. n end
    return #parts > 0 and table.concat(parts, ",") or "-"
end

local function fail(why) return { ok = false, why = why } end

local function done(snap, ok, why)
    if not ok then return fail(why) end
    return { ok = true, state = snap.state, settled = snap.settled == true }
end

-- verdict "present": the recorded car is in the world. PACKED -> VOID (that pack never took effect); UNPACKED ->
--   settled (the spawned car is real; its unpack is marked as known, and the guard then clears the capsule's cargo
--   copy). A car the server cannot find needs `checked` (an admin saw it on site).
-- verdict "missing": refused with CAR_EXISTS while the server has that car loaded; needs `checked` when the recorded
--   spot is not loaded either. PACKED -> settled (restorable as usual); UNPACKED -> PACKED, settled (the player
--   throws again: car and cargo come back).
-- Only uncertain PACKED/UNPACKED records.
function Admin.resolve(admin, capsuleId, verdict, note, checked)
    if not M.isAdmin(admin) then return fail("NOT_ADMIN") end
    local snap, why = Store.read(capsuleId)
    if not snap then return fail(why) end
    if not Store.uncertain(capsuleId, snap) or (snap.state ~= "PACKED" and snap.state ~= "UNPACKED") then
        return fail("NOT_UNCERTAIN")
    end
    local e = Store.recordedCar(snap)
    local car = Store.findLoadedVehicle(e.car, snap.script)
    local info = { ev = "RESOLVED", verdict = verdict, note = note, car = e.car }
    local to -- new state; nil when the verdict only marks the record settled
    if verdict == "present" then
        if not car and not checked then return fail("CHECK_SITE") end
        if snap.state == "PACKED" then to = "VOID" end
    elseif verdict == "missing" then
        if car then return fail("CAR_EXISTS") end
        if not checked and not (e.x and getCell():getGridSquare(e.x, e.y, e.z or 0)) then return fail("CHECK_SITE") end
        if snap.state == "UNPACKED" then to = "PACKED" end
    else
        return fail("BAD_ARGS")
    end
    if to then return done(snap, Store.setState(capsuleId, snap, to, admin, info, true)) end
    snap.settled = true
    local ok, why = Store.event(capsuleId, snap, "RESOLVED", admin, info)
    if ok and snap.state == "UNPACKED" then Store.mark(capsuleId) end
    return done(snap, ok, why)
end

-- Spawns the recorded vehicle again at (x, y, z), without cargo (history lists it), for a PACKED record (uncertain
-- ones need `checked`) or an uncertain UNPACKED one. RESTORED is written before the spawn, so the old capsule can
-- never unpack afterwards; a failed spawn puts the previous state back. `dir`: the admin panel always sends the spot
-- picked with the restore cursor, so the vehicle faces it and its ground must be clear, the same check a throw's
-- landing makes. Without it (debug commands) the vehicle faces north and the ground is not checked. A capsule out in
-- an Economy trade (listed, auctioned) is refused: its buyer would get a capsule whose vehicle is already back.
function Admin.restore(admin, capsuleId, x, y, z, note, checked, dir)
    if not M.isAdmin(admin) then return fail("NOT_ADMIN") end
    local snap, why = Store.read(capsuleId)
    if not snap then return fail(why) end
    local uncertain = Store.uncertain(capsuleId, snap)
    if not (snap.state == "PACKED" or (snap.state == "UNPACKED" and uncertain)) then return fail("NOT_RESTORABLE") end
    if type(snap.escrow) == "table" and snap.escrow.active then return fail("IN_TRADE") end
    if Store.findLoadedVehicle(Store.recordedCar(snap).car, snap.script) then return fail("CAR_EXISTS") end
    if uncertain and not checked then return fail("CHECK_SITE") end
    local square = x and y and getCell():getGridSquare(x, y, z or 0)
    if not square then return fail("BLOCKED") end
    local sc = getScriptManager():getVehicle(snap.script)
    if not sc then return fail("SCRIPT_MISSING") end
    if dir and M.Footprint.clear(sc, x, y, z or 0, dir) then return fail("PICK_BLOCKED") end
    local prev = { state = snap.state, settled = snap.settled, uncertain = uncertain }
    snap.escrow = nil -- a finished Economy trade's cargo copy: the old capsule can never unpack again
    local ok, werr = Store.setState(capsuleId, snap, "RESTORED", admin, { ev = "RESTORE_START", note = note })
    if not ok then return fail(werr) end
    local vehicle, verr = Unpack.spawn(snap, square, dir or "N")
    if not vehicle then
        Store.undo(capsuleId, snap, prev, admin, "RESTORE_FAILED", verr)
        return fail(verr)
    end
    local sq = vehicle:getSquare()
    Store.event(capsuleId, snap, "RESTORED", admin, { x = sq:getX(), y = sq:getY(), z = sq:getZ(),
        car = vehicle:getSqlId(), note = note, items = manifest(snap) })
    return { ok = true, state = snap.state, vehicleId = vehicle:getId(), sqlId = vehicle:getSqlId() }
end

return Admin
