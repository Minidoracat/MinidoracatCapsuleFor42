-- Pack & Throw: admin API (server). Resolve records a crash left uncertain, and restore a lost vehicle.
-- Callers: the debug commands now (Commands.lua), the admin panel later. Every entry checks M.isAdmin itself.
-- Results are { ok = true, state } or { ok = false, why }.
if isClient() then return end
require "MinidoracatPackThrow/Core"
require "MinidoracatPackThrow/Store"
require "MinidoracatPackThrow/Unpack"
require "MinidoracatPackThrow/Footprint"
require "MinidoracatPackThrow/Rules"
local M = MinidoracatPackThrow
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

-- The refusal when the recorded vehicle or animal is still loaded in the world.
local function exists(snap) return snap.kind == "animal" and "ANIMAL_EXISTS" or "CAR_EXISTS" end

-- verdict "present": the recorded car is in the world. PACKED -> VOID (that pack never took effect); UNPACKED ->
--   settled (the spawned car is real; its unpack is marked as known, and the guard then clears the capsule's cargo
--   copy). A car the server cannot find needs `checked` (an admin saw it on site).
-- verdict "missing": refused with CAR_EXISTS (an animal: ANIMAL_EXISTS) while the server has it loaded; needs `checked`
--   when the recorded spot is not loaded either. PACKED -> settled (restorable as usual); UNPACKED -> PACKED, settled
--   (the player throws again: car and cargo come back).
-- Only uncertain PACKED/UNPACKED records.
function Admin.resolve(admin, capsuleId, verdict, note, checked)
    if not M.isAdmin(admin) then return fail("NOT_ADMIN") end
    local snap, why = Store.read(capsuleId)
    if not snap then return fail(why) end
    if not Store.uncertain(capsuleId, snap) or (snap.state ~= "PACKED" and snap.state ~= "UNPACKED") then
        return fail("NOT_UNCERTAIN")
    end
    local e = Store.recordedCar(snap)
    local car = Store.findRecorded(snap)
    local info = { ev = "RESOLVED", verdict = verdict, note = note, car = e.car, animal = e.animal }
    local to -- new state; nil when the verdict only marks the record settled
    if verdict == "present" then
        if not car and not checked then return fail("CHECK_SITE") end
        if snap.state == "PACKED" then to = "VOID" end
    elseif verdict == "missing" then
        if car then return fail(exists(snap)) end
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

-- Spawns the recorded vehicle (or animal) again at (x, y, z), without cargo (history lists it), for a PACKED record
-- (uncertain ones need `checked`) or an uncertain UNPACKED one. RESTORED is written before the spawn, so the old capsule
-- can never unpack afterwards; a failed spawn puts the previous state back. `dir`: the admin panel always sends the
-- spot picked with the restore cursor, so the vehicle faces it and its ground (an animal: its one square) must be
-- clear and outside safehouses this admin may not touch (SAFEHOUSE; Capability.CanGoInsideSafehouses passes), the same
-- checks a throw's landing makes. Without it (debug commands) the vehicle faces north and the ground is not checked.
-- A capsule out in an Economy trade (listed, auctioned) is refused: its buyer would get a capsule whose vehicle is
-- already back.
function Admin.restore(admin, capsuleId, x, y, z, note, checked, dir)
    if not M.isAdmin(admin) then return fail("NOT_ADMIN") end
    local snap, why = Store.read(capsuleId)
    if not snap then return fail(why) end
    local uncertain = Store.uncertain(capsuleId, snap)
    if not (snap.state == "PACKED" or (snap.state == "UNPACKED" and uncertain)) then return fail("NOT_RESTORABLE") end
    if type(snap.escrow) == "table" and snap.escrow.active then return fail("IN_TRADE") end
    if Store.findRecorded(snap) then return fail(exists(snap)) end
    if uncertain and not checked then return fail("CHECK_SITE") end
    local square = x and y and getCell():getGridSquare(x, y, z or 0)
    if not square then return fail("BLOCKED") end
    local sc = snap.kind ~= "animal" and getScriptManager():getVehicle(snap.script)
    if snap.kind ~= "animal" and not sc then return fail("SCRIPT_MISSING") end
    if dir then
        local why, box
        if snap.kind == "animal" then
            why, box = M.Footprint.animalClear(x, y, z or 0)
        else
            why, box = M.Footprint.clear(sc, x, y, z or 0, dir)
        end
        if why then return fail("PICK_BLOCKED") end
        if M.Rules.safehouseWhyNot(admin, box, z or 0) then return fail("SAFEHOUSE") end
    end
    local prev = { state = snap.state, settled = snap.settled, uncertain = uncertain }
    snap.escrow = nil -- a finished Economy trade's cargo copy: the old capsule can never unpack again
    local ok, werr = Store.setState(capsuleId, snap, "RESTORED", admin, { ev = "RESTORE_START", note = note })
    if not ok then return fail(werr) end
    local thing, verr = Unpack.spawn(snap, square, dir or "N")
    if not thing then
        Store.undo(capsuleId, snap, prev, admin, "RESTORE_FAILED", verr)
        return fail(verr)
    end
    local e = Unpack.placed(snap, thing)
    e.note, e.items = note, manifest(snap)
    Store.event(capsuleId, snap, "RESTORED", admin, e)
    if snap.kind == "animal" then return { ok = true, state = snap.state, animalId = e.animal } end
    return { ok = true, state = snap.state, vehicleId = thing:getId(), sqlId = e.car }
end

return Admin
