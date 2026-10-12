-- Universal Capsule (client): server messages for players (module MinidoracatCapsule). Effects go to Effects.lua,
-- capsule info to the landing cursor, results become a Toast or a Dialog of the family UI framework
-- (MinidoracatUIFor42, API 1 rev 7: toast + dialog). Without the framework: halo text above the player.
-- SP has no server->client channel; the server code calls M.onServerCommand directly (PlayerCommands.send).
require "MinidoracatCapsule/Core"
require "MinidoracatCapsule/Effects"
require "MinidoracatCapsule/Info"
require "MinidoracatCapsule/Rules"
local okUI = pcall(require, "MinidoracatUI/V1")
local M = MinidoracatCapsule
local Notify = { shown = {} }
M.Notify = Notify

local function ui()
    local UI = okUI and MinidoracatUI and MinidoracatUI.v1
    if UI and UI.API_MAJOR == 1 and (UI.API_REVISION or 0) >= 7 then return UI end
    return nil
end

local function remember(kind, title, text)
    Notify.shown[#Notify.shown + 1] = { kind = kind, title = title, text = text }
    M.log("NOTIFY " .. kind .. " " .. tostring(title) .. " | " .. tostring(text))
end

-- holdMs: how long it stays (framework default 3 s); failures the player must act on go to Notify.dialog instead.
-- No text: the title alone is the message, without a title bar (the toast needs a message; title and message both set
-- showed the line twice, e.g. "Unpacked: X" with ReturnEmptyCapsule off).
function Notify.toast(title, text, bad, holdMs)
    remember(bad and "toast-bad" or "toast", title, text)
    local UI = ui()
    if UI and UI.CAPABILITIES.toast then
        UI.Toast.show({ title = text and title or nil, message = text or title, maxLines = 4, holdMs = holdMs })
        return
    end
    local player = getPlayer()
    if player then
        local line = text and (title .. " " .. text) or title
        if bad then HaloTextHelper.addBadText(player, line) else HaloTextHelper.addGoodText(player, line) end
    end
end

function Notify.dialog(title, text)
    remember("dialog", title, text)
    local UI = ui()
    if UI and UI.CAPABILITIES.dialog then
        Notify.current = UI.Dialog.show({ title = title, text = text, width = 420, opaque = true,
            confirmText = getText("IGUI_MinidoracatCapsule_GotIt") })
        return
    end
    local player = getPlayer()
    if player then HaloTextHelper.addBadText(player, title) end
end

-- Display name of a vehicle script in this client's language (same rule as ISVehicleMenu.getVehicleDisplayName).
function Notify.vehicleName(scriptName)
    local sc = scriptName and getScriptManager():getVehicle(scriptName)
    if not sc then return scriptName or "?" end
    local name = sc:getName()
    local text = getTextOrNull("IGUI_VehicleName" .. (sc:getCarModelName() or name))
    if string.find(name, "Burnt") then
        local unburnt = getTextOrNull("IGUI_VehicleName" .. string.gsub(name, "Burnt", ""))
        text = getText("IGUI_VehicleNameBurntCar", unburnt or text or name)
    end
    return text or name
end

-- Player-facing text for a reason code (cursor, dialogs, toasts). release: the code is about a landing spot (throw,
-- press, admin restore), worded by Why_<code>_RELEASE where there is one (SAFEHOUSE: packing says "in someone else's
-- safehouse", landing "the spot is in someone else's safehouse").
function Notify.reason(code, release)
    local key = "IGUI_MinidoracatCapsule_Why_" .. tostring(code)
    return (release and getTextOrNull(key .. "_RELEASE")) or getTextOrNull(key)
        or getText("IGUI_MinidoracatCapsule_Why_OTHER", tostring(code))
end

-- Whether this player may pack this vehicle, and the permission text for the menu row and the refusal toast.
-- VehicleManager decides for a claimed vehicle (its Tow permission, Rules.mayPack); its own wording covers rental
-- locks, quarantine, paused faction shares, and an admin whose override is off (every override use is logged there).
local PERM_TEXT = { VM = "PermOwner", SHARED = "PermShared", KEY = "PermKey", ADMIN = "PermAdmin", ANY = "PermAny" }
local VM_REASON = { RENT_LOCKED = true, QUARANTINED = true, FACTION_PAUSED = true, NOT_READY = true }
function Notify.permission(player, vehicle)
    local may, mode, why = M.Rules.mayPack(player, vehicle)
    local tow = getTextOrNull("IGUI_MVM_ActionShort_TOW") or "Tow"
    if may then return true, getText("IGUI_MinidoracatCapsule_" .. PERM_TEXT[mode], tow) end
    if mode == "VM" then
        local own = VM_REASON[why] and getTextOrNull("IGUI_MVM_Reason_" .. tostring(why))
            or M.Rules.isAdmin(player) and getTextOrNull("IGUI_MVM_ProtectedAdmin")
        if own then return false, own end
    end
    return false, getText("IGUI_MinidoracatCapsule_" .. PERM_TEXT[mode] .. "No", tow)
end

-- local time like the admin panel (Kahlua's os.date is UTC: 06:28 for a 14:28 restore in UTC+8)
local function stamp(t)
    return t and M.Info.date(t) or "?"
end

-- One rich-text tooltip row (ISToolTip description): a check or a red mark, then the text in the player's
-- good / bad highlight colour. Vanilla icons instead of check / cross glyphs: those are missing from vanilla fonts.
local TICK, MISS = "media/ui/Tick_Mark-10.png", "media/ui/Moodle_internal_minus_red.png"
function Notify.row(ok, text)
    local c = ok and getCore():getGoodHighlitedColor() or getCore():getBadHighlitedColor()
    return string.format(" <IMAGE:%s,12,12> <RGB:%.2f,%.2f,%.2f> %s <LINE> ", ok and TICK or MISS,
        c:getR(), c:getG(), c:getB(), text)
end

local Handlers = {}

function Handlers.fx(args) M.Effects.play(args) end

function Handlers.capsuleInfo(args)
    if M.ThrowCursor then M.ThrowCursor.onInfo(args) end
end

-- A refused pack stays until the player closes it (a toast faded in 3 s while they looked elsewhere; review).
function Handlers.packed(args)
    if args.ok then return end
    local text = Notify.reason(args.why)
    -- refused for permission: the same reason the menu row gives (VehicleManager's wording included)
    local vehicle = args.why == "NOT_ALLOWED" and args.vehicleId and getVehicleById(args.vehicleId)
    if vehicle then text = select(2, Notify.permission(getPlayer(), vehicle)) end
    Notify.dialog(getText(args.kind == "animal" and "IGUI_MinidoracatCapsule_PackAnimalFailed"
        or "IGUI_MinidoracatCapsule_PackFailed"), text)
end

-- A thrown empty capsule (mode "capture"): a toast either way; a miss says why and where the capsule went.
local function captured(args)
    if args.ok then
        local name = args.kind == "animal" and M.Info.animalName(args.animal) or Notify.vehicleName(args.script)
        Notify.toast(getText("IGUI_MinidoracatCapsule_Captured", name), getText("IGUI_MinidoracatCapsule_CapturedHere"))
        return
    end
    local text = Notify.reason(args.why)
    -- refused for permission: the same reason the vehicle menu row gives (VehicleManager's wording included)
    local vehicle = args.why == "NOT_ALLOWED" and args.vehicleId and getVehicleById(args.vehicleId)
    if vehicle then text = select(2, Notify.permission(getPlayer(), vehicle)) end
    Notify.toast(getText("IGUI_MinidoracatCapsule_CaptureFailed", text),
        getText(args.dropped and "IGUI_MinidoracatCapsule_CaptureDropped" or "IGUI_MinidoracatCapsule_CaptureKept"), true, 8000)
end

function Handlers.landed(args)
    if args.mode == "capture" then return captured(args) end
    local animal = args.kind == "animal" and "Animal" or ""
    if args.ok then
        local name = animal ~= "" and M.Info.animalName(args.animal) or Notify.vehicleName(args.script)
        Notify.toast(getText("IGUI_MinidoracatCapsule_Unpacked", name),
            args.returned and getText("IGUI_MinidoracatCapsule_EmptyBack") or nil)
    elseif args.why == "BLOCKED" then
        local body = args.mode == "press" and "IGUI_MinidoracatCapsule_BlockedPress"
            or "IGUI_MinidoracatCapsule_BlockedThrow"
        Notify.dialog(getText("IGUI_MinidoracatCapsule_BlockedTitle" .. animal),
            getText(body .. animal, Notify.reason(args.reason)))
    elseif args.why == "UNCERTAIN" then
        Notify.dialog(getText("IGUI_MinidoracatCapsule_UncertainTitle"),
            getText("IGUI_MinidoracatCapsule_UncertainBody", tostring(args.capsuleId)))
    elseif args.why == "NOT_PACKED" or args.why == "CLEARED" then
        local state = getTextOrNull("IGUI_MinidoracatCapsule_State_" .. tostring(args.state))
            or getText("IGUI_MinidoracatCapsule_State_UNPACKED")
        Notify.dialog(getText("IGUI_MinidoracatCapsule_UsedTitle"),
            getText("IGUI_MinidoracatCapsule_UsedBody", stamp(args.t), state, tostring(args.capsuleId)))
    else
        local text = Notify.reason(args.why, true)
        if args.feet and args.dropped then text = getText("IGUI_MinidoracatCapsule_DroppedAtFeet", text) end
        Notify.dialog(getText("IGUI_MinidoracatCapsule_UnpackFailed"), text)
    end
end

function M.onServerCommand(command, args)
    local fn = Handlers[command]
    if fn then fn(args or {}) end
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= M.MODULE then return end
    M.onServerCommand(command, args)
end)

return Notify
