-- Vehicle Capsule (client): the family UI framework (MinidoracatUIFor42, require= in mod.info) for the preview
-- window and the admin panel. Needs API rev 13 (Dock; chip buttons and Text.fit are rev 11, Slider rev 9) with the
-- window, controls and virtualList capabilities. Without it Kit.ok is false: the windows do not open and the entry
-- points say so (fail-soft, no half-built UI), the tooltip does not need it.
require "MinidoracatVehicleCapsule/Core"
local M = MinidoracatVehicleCapsule
local Kit = {}
M.UIKit = Kit

-- widget files are not loaded by V1 and may sort after this file: require them ourselves
if not (MinidoracatUI and MinidoracatUI.v1) then pcall(require, "MinidoracatUI/V1") end
pcall(require, "MinidoracatUI/VirtualList")
pcall(require, "MinidoracatUI/Widgets/Controls")
pcall(require, "MinidoracatUI/Widgets/Window")
pcall(require, "MinidoracatUI/Widgets/Toast")
pcall(require, "MinidoracatUI/Widgets/Dock")
local UI = MinidoracatUI and MinidoracatUI.v1
local CAPS = UI and UI.CAPABILITIES
Kit.UI, Kit.CAPS = UI, CAPS
Kit.ok = UI ~= nil and UI.API_MAJOR == 1 and UI.API_REVISION >= 13 and CAPS.window == true and CAPS.controls == true
    and CAPS.virtualList == true and CAPS.slider == true and UI.Text ~= nil and type(UI.Text.fit) == "function"
if not Kit.ok then
    M.log("preview and admin panel need MinidoracatUIFor42 API rev 13, found rev "
        .. tostring(UI and UI.API_REVISION))
    return Kit
end

Kit.theme = UI.Theme.create({ variant = "dark" })
Kit.COL = Kit.theme.colors
Kit.FS = UIFont.Small
Kit.FH = getTextManager():getFontHeight(UIFont.Small)

function Kit.text(el, s, x, y, token, font)
    local c = Kit.COL[token or "text"] or Kit.COL.text
    el:drawText(tostring(s), x, y, c.r, c.g, c.b, c.a, font or Kit.FS)
end

function Kit.fit(s, w, font)
    return UI.Text.fit(tostring(s), math.max(0, w), font or Kit.FS)
end

function Kit.wrap(s, w)
    if CAPS.textWrap and type(UI.Text.wrap) == "function" then return UI.Text.wrap(s, w, Kit.FS) end
    return { Kit.fit(s, w) }
end

function Kit.measure(s, font)
    return getTextManager():MeasureStringX(font or Kit.FS, tostring(s))
end

-- Toast when the framework has it, else the vanilla halo text over the player.
function Kit.notify(title, message)
    if CAPS.toast and UI.Toast then
        UI.Toast.show({ title = title, message = message })
    else
        local p = getSpecificPlayer(0)
        if p then HaloTextHelper.addText(p, message) end
    end
end

return Kit
