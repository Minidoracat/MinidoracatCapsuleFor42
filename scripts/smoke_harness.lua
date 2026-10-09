--[[
煙霧測試骨架：用假的 PZ 全域載入**真正的** MOD Lua，跑行為情境並斷言結果。

    lua scripts/smoke_harness.lua        （repo 根目錄執行；標準 Lua 5.x 即可）

為什麼需要（兩類 luac -p 抓不到的錯誤，皆為正式服實際事故）：
- 改函式簽章漏改呼叫點：語法完全合法，要等該路徑真的執行才炸
  （實例：hotspotKey 兩參數改三參數，刪除成功後的 log 聚合路徑必崩）
- 邏輯回歸：安全把關（範圍／阻隔／保護規則）被改壞時，「執行到並斷言」是唯一防線

限制（必須誠實面對）：這是標準 Lua，不是遊戲的 Kahlua。
- 標準 Lua 有 next/xpcall，Kahlua 沒有——本 harness **測不出**誤用，
  那由 scripts/verify_mod.py 的靜態掃描負責（發版前兩者都要跑）
- Kahlua 專屬行為（table.sort 遞迴深度、Java instance field 不暴露、rawget 呼叫形式、
  每個 table 都是 LinkedHashMap 的記憶體成本）只能靠反編譯查證與實機測試

寫情境的原則：
- 情境要「執行到會炸的路徑」——刪除後的收尾、跨 tick 的第二輪、聚合輸出，都是重災區
- 安全邊界要有**反面**斷言（範圍外／被阻隔／受保護的對象必須存活），不是只測 happy path
- 新防線寫完先「植入違規證明它會抓」再信任它——測不出來的測試等於沒有測試
]]

-- 家族佈局固定，直接填死最省事；scaffold 時由模板替換佔位符
local MEDIA = "MOD/MinidoracatVehicleCapsuleFor42/Contents/mods/MinidoracatVehicleCapsuleFor42/42/media/lua"

-- ===== 假的 PZ 全域（依 MOD 實際用到的 API 增補）=====
local nowMs = 5000000
local logLines = {}

function getTimestampMs() return nowMs end
function isClient() return false end
function isServer() return true end
function writeLog(_, text) logLines[#logLines + 1] = text end
function getText(key) return key end
local realPrint = print
local quiet = false
function print(...) if not quiet then realPrint(...) end end

Events = setmetatable({}, { __index = function() return { Add = function() end } end })

-- 假物品／容器：只做 Store、Guard、Admin 用到的方法。AddItem 刻意不從舊容器移除（漏呼叫 Remove 會被抓到）
local nextItemId = 1000
local function javaList(l)
    return { size = function() return #l end, get = function(_, i) return l[i + 1] end }
end
local function newContainer(holder)
    local c = { list = {}, holder = holder }
    function c:getItems() return javaList(self.list) end
    function c:getContainingItem() return self.holder end
    function c:AddItem(it) self.list[#self.list + 1] = it; it.container = self; return it end
    function c:Remove(it)
        for i, x in ipairs(self.list) do
            if x == it then table.remove(self.list, i); it.container = nil; return end
        end
    end
    c.DoRemoveItem = c.Remove
    function c:getItemWithIDRecursiv(id)
        for _, x in ipairs(self.list) do
            if x.id == id then return x end
            local r = x.inv and x.inv:getItemWithIDRecursiv(id)
            if r then return r end
        end
    end
    function c:getAllTypeRecurse(t)
        local out = {}
        local function walk(cc)
            for _, x in ipairs(cc.list) do
                if x.type == t then out[#out + 1] = x end
                if x.inv then walk(x.inv) end
            end
        end
        walk(self)
        return javaList(out)
    end
    return c
end
local function newItem(fullType, isContainer)
    nextItemId = nextItemId + 1
    local it = { id = nextItemId, type = fullType }
    function it:getID() return self.id end
    function it:getFullType() return self.type end
    function it:getContainer() return self.container end
    function it:getWorldItem() return nil end
    if isContainer then
        it.inv = newContainer(it)
        function it:getInventory() return self.inv end
    end
    return it
end
function instanceof(o, cls) return cls == "InventoryContainer" and type(o) == "table" and o.inv ~= nil end
function instanceItem(t)
    return newItem(t, t == "MinidoracatVehicleCapsule.LoadedCapsule" or t == "Base.Bag_Schoolbag")
end
function sendAddItemToContainer() end
function sendRemoveItemFromContainer() end
Capability = { ManipulateVehicle = "ManipulateVehicle" }
function checkPermissions(p) return p.admin == true end
local function newPlayer(name, admin)
    local p = { admin = admin, inv = newContainer(nil) }
    function p:getUsername() return name end
    function p:getX() return 100.5 end
    function p:getY() return 200.7 end
    function p:getZ() return 0 end
    function p:getInventory() return self.inv end
    function p:removeFromHands() end
    function p:isEquipped(it) return it.equipped == true end
    function p:isAttachedItem() return false end
    return p
end
-- 假世界：已載入的車（sqlId）與已載入的格子
local loadedCars, loadedSquares = {}, {}
function getCell()
    return {
        getVehicles = function()
            return { iterator = function()
                local i = 0
                return { hasNext = function() return i < #loadedCars end,
                    next = function() i = i + 1; return loadedCars[i] end }
            end }
        end,
        getGridSquare = function(_, x, y) return loadedSquares[tostring(x) .. "," .. tostring(y)] end,
    }
end
local function fakeCar(sqlId, script)
    return { getSqlId = function() return sqlId end, getScriptName = function() return script or "Base.PickUpTruck" end }
end
function getScriptManager() return { getVehicle = function(_, s) return s == "Base.PickUpTruck" end } end
function getOnlinePlayers() return javaList({}) end

-- 假檔案系統：照 getFileWriter 的副檔名白名單（LuaManager.java:1035），且可植入「靜默丟寫」與「寫壞」
local files, dropWrites, corruptWrites = {}, false, false
local WHITELIST = { ini = true, cfg = true, txt = true, log = true, json = true }
function getFileWriter(path, _, append)
    if path:find("%.%.") or not WHITELIST[path:match("%.(%w+)$") or ""] then return nil end
    local buf = append and files[path] or ""
    return {
        write = function(_, s) buf = buf .. s end,
        close = function()
            if dropWrites then return end -- PrintWriter 吞掉 I/O 錯誤：呼叫端什麼都看不到
            files[path] = corruptWrites and buf:sub(1, #buf - 1) or buf
        end,
    }
end
function getFileReader(path, _)
    local text = files[path]
    if not text then return nil end
    local lines, i = {}, 0
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    if text:sub(-1) == "\n" then lines[#lines] = nil end
    return {
        readLine = function() i = i + 1; return lines[i] end,
        close = function() end,
    }
end

-- ===== 載入受測程式碼 =====
local loaded = {}
function require(name)
    if loaded[name] then return true end
    loaded[name] = true
    for _, dir in ipairs({ "shared", "server", "client" }) do
        local chunk = loadfile(MEDIA .. "/" .. dir .. "/" .. name .. ".lua")
        if chunk then chunk() return true end
    end
    error("require 找不到: " .. name)
end

require "MinidoracatVehicleCapsule/Core"
require "MinidoracatVehicleCapsule/Json"
require "MinidoracatVehicleCapsule/Store"
require "MinidoracatVehicleCapsule/Guard"
require "MinidoracatVehicleCapsule/Admin"
local M = MinidoracatVehicleCapsule
local Json, Store, Guard, Admin = M.Json, M.Store, M.Guard, M.Admin

-- ===== 測試工具 =====
local failures = 0
local function check(ok, label)
    if ok then print("  PASS  " .. label)
    else failures = failures + 1; print("  FAIL  " .. label) end
end

-- 逐值比對（型別也要一樣：數字 key 不能變字串）；回傳第一個不同的路徑
local function diff(a, b, path)
    path = path or "$"
    if type(a) ~= type(b) then return path .. " type " .. type(a) .. "/" .. type(b) end
    if type(a) ~= "table" then
        if a ~= b then return path .. " " .. tostring(a) .. "~=" .. tostring(b) end
        return nil
    end
    for k, v in pairs(a) do
        local d = diff(v, b[k], path .. "[" .. type(k) .. ":" .. tostring(k) .. "]")
        if d then return d end
    end
    for k in pairs(b) do
        if a[k] == nil then return path .. " extra key " .. type(k) .. ":" .. tostring(k) end
    end
    return nil
end

local function roundTrip(v)
    local text, bad = Json.encode(v)
    if not text then return nil, "encode failed at " .. tostring(bad) end
    local back, err = Json.decode(text)
    if err then return nil, "decode failed: " .. err end
    return back, text
end

local player = {
    getUsername = function() return "tester" end,
    getX = function() return 100.5 end, getY = function() return 200.7 end, getZ = function() return 0 end,
}

-- ===== 情境 =====
print("Json：往返保留型別與數值")
local nasty = {
    nested = { a = { b = { c = { d = "deep" } } } },
    [1] = "one", [2] = "two", [10] = "ten", [-3] = "neg", [1.5] = "half",
    ["1"] = "string one", ["#tag"] = "hash", ["##x"] = "double hash", ["#5"] = "hash five",
    unicode = "中文 日本語 한국어 é ✓",
    escapes = 'quote " backslash \\ newline \n cr \r tab \t ctrl \1 del \127 slash /',
    empty = {},
    emptyStr = "",
    floats = { 0.1, 0.1 + 0.2, 1 / 3, 1e-300, 1e300, -2.5, 123456789.125, 2 ^ 53, -(2 ^ 53), 1e14, 1e15 + 0.5 },
    bools = { t = true, f = false },
    ints = { 0, -0, 7, 4294967296, 99999999999 },
}
local back, text = roundTrip(nasty)
check(back ~= nil, "巢狀刁鑽值可編碼並解碼（" .. tostring(text and #text) .. " bytes）")
check(back and diff(nasty, back) == nil, "逐值相等，型別不變：" .. tostring(back and diff(nasty, back)))
check(back and back[1] == "one" and back["1"] == "string one", "數字 key 1 與字串 key \"1\" 不互相覆蓋")
check(back and back["#tag"] == "hash" and back["##x"] == "double hash" and back["#5"] == "hash five", "# 開頭字串 key 原樣保留")
check(text and not text:find("\n"), "輸出單行（讀回比對逐行串接）")
check(Json.encode({}) == "{}", "空表編成 {}")
check(select(2, Json.decode("{} x")) ~= nil, "尾端垃圾拒收")
check(select(2, Json.decode('{"#abc":1}')) ~= nil, "壞數字 key 拒收")
check(Json.decode('{"a":"\\u0041\\u00e9"}').a == "A\195\169", "\\u 跳脫解碼（標準 Lua 轉 UTF-8）")

print("Json：拒收不能存的值並回傳路徑")
local function rejects(v, want, label)
    local text2, path = Json.encode(v)
    check(text2 == nil and path == want, label .. "（path=" .. tostring(path) .. "）")
end
rejects({ modData = { foo = { bar = function() end } } }, "modData.foo.bar", "function")
rejects({ modData = { foo = { bar = io.stdout } } }, "modData.foo.bar", "userdata")
rejects({ x = { y = 0 / 0 } }, "x.y", "NaN")
rejects({ x = { y = math.huge } }, "x.y", "inf")
rejects({ x = { [true] = 1 } }, "x.<boolean key>", "boolean key")
local loop = {}; loop.self = loop
check(Json.encode(loop) == nil, "循環參照不會無限遞迴")

print("Json.storable：照引擎存檔規則跳過 userdata/function/NaN/inf/布林 key，其餘逐值保留")
local mixed = {
    keep = nasty,
    foo = { bar = io.stdout, fn = function() end, ok = 1 },
    _vehicle = io.stdout,
    nan = 0 / 0, inf = math.huge,
    [true] = "bool key",
}
local skipped = {}
local clean = Json.storable(mixed, "modData", skipped)
local want = {
    ["modData.foo.bar"] = true, ["modData.foo.fn"] = true, ["modData._vehicle"] = true,
    ["modData.nan"] = true, ["modData.inf"] = true, ["modData.<boolean key>"] = true,
}
local got = {}
for _, p in ipairs(skipped) do got[p] = true end
check(diff(want, got) == nil and #skipped == 6, "skipped 正好列出 6 條路徑：" .. table.concat(skipped, ","))
check(diff(nasty, clean.keep) == nil and clean.foo.ok == 1 and clean.foo.bar == nil, "可存的值逐值保留")
local cleanBack = roundTrip(clean)
check(cleanBack and diff(clean, cleanBack) == nil, "storable 結果一定能 JSON 往返")
local deep = {}; deep.self = deep
local dskip = {}
Json.storable(deep, "m", dskip)
check(#dskip == 1, "循環參照在深度上限處截斷並記一條路徑")

print("Store：寫後讀回、狀態只轉一次")
local snap = { v = 1, state = "PACKED", settled = true, script = "Base.PickUpTruck", modData = nasty, history = {} }
check(Store.write(42, snap) == true, "寫入並讀回一致")
check(files["MinidoracatVehicleCapsule/packs/42.json"] ~= nil, "落在 packs/<id>.json")
local r = Store.read(42)
check(r and diff(snap, r) == nil, "read 讀回與寫入相同")
check(select(2, Store.read(43)) == "NO_SNAPSHOT", "沒有檔案回 NO_SNAPSHOT")
files["MinidoracatVehicleCapsule/packs/44.json"] = "{broken"
check(select(2, Store.read(44)) == "CORRUPT", "壞檔回 CORRUPT")

local claimed = Store.claim(42, player)
check(claimed and claimed.state == "UNPACKED", "claim：PACKED -> UNPACKED")
check(Store.read(42).state == "UNPACKED", "claim 已落盤（生車前）")
local again, why = Store.claim(42, player)
check(again == nil and why == "NOT_PACKED", "第二次 claim 被拒 NOT_PACKED")
local h = Store.read(42).history
check(#h == 1 and h[1].ev == "REJECTED" and h[1].by == "tester", "被拒記 REJECTED（by=" .. tostring(h[1] and h[1].by) .. "）")
check(#logLines >= 1 and logLines[#logLines]:find("REJECTED capsule=42", 1, true) ~= nil, "REJECTED 寫進 writeLog")
check(Store.read(42).settled == nil, "claim 清掉 settled（新狀態要重新落盤）")

Store.write(50, { state = "PACKED", settled = true, history = {} })
local s50 = Store.claim(50, player)
check(Store.release(50, s50, player, "BLOCKED") == true and Store.read(50).state == "PACKED", "生車失敗 release 回 PACKED")
check(Store.read(50).history[1].ev == "UNPACK_FAILED" and Store.read(50).history[1].why == "BLOCKED", "release 記 UNPACK_FAILED 與原因")
check(Store.setState(50, Store.read(50), "RESTORED", player, { car = 7 }) == true, "PACKED -> RESTORED")
check(select(2, Store.claim(50, player)) == "NOT_PACKED", "RESTORED 後 claim 被拒")
check(select(2, Store.release(50, Store.read(50), player, "x")) == "BAD_TRANSITION", "RESTORED 不能 release")

print("Store：寫入失敗要被發現（植入違規）")
dropWrites = true
quiet = true
local ok1, why1 = Store.write(60, { state = "PACKED" })
quiet = false
dropWrites = false
check(ok1 == nil and why1 == "WRITE_FAILED", "靜默丟寫 -> WRITE_FAILED")
Store.write(61, { state = "PACKED", settled = true, history = {} })
corruptWrites = true
quiet = true
local c61, cwhy = Store.claim(61, player)
quiet = false
corruptWrites = false
check(c61 == nil and cwhy == "WRITE_FAILED", "claim 寫壞 -> WRITE_FAILED，不回快照")
local ok2, why2, path2 = Store.write(62, { modData = { bad = function() end } })
check(ok2 == nil and why2 == "MODDATA_UNSUPPORTED" and path2 == "modData.bad", "存不成 JSON -> MODDATA_UNSUPPORTED＋路徑")
check(files["MinidoracatVehicleCapsule/packs/62.json"] == nil, "被拒時不留快照檔")

print("Store：狀態轉換表（只有表上的 5 條箭頭）")
local STATES = { "PACKED", "UNPACKED", "RESTORED", "VOID" }
local ARROWS = { ["PACKED>UNPACKED"] = true, ["PACKED>RESTORED"] = true, ["PACKED>VOID"] = true,
    ["UNPACKED>PACKED"] = true, ["UNPACKED>RESTORED"] = true }
local tid, badArrows = 100, {}
quiet = true
for _, from in ipairs(STATES) do
    for _, to in ipairs(STATES) do
        tid = tid + 1
        Store.write(tid, { state = from, settled = true, history = {} })
        local ok = Store.setState(tid, Store.read(tid), to, player) == true
        local after = Store.read(tid)
        local want = ARROWS[from .. ">" .. to] == true
        if ok ~= want or after.state ~= (ok and to or from) or (ok and after.history[1].ev ~= to) then
            badArrows[#badArrows + 1] = from .. ">" .. to
        end
    end
end
quiet = false
check(#badArrows == 0, "16 組只有表上的允許，其餘 BAD_TRANSITION 且不動檔案：" .. table.concat(badArrows, ","))

print("Store：落盤標記 settled 與 uncertain")
local t0 = nowMs
Store.write(200, { state = "PACKED", history = {} })
Store.schedule(200)
check(not Store.uncertain(200, Store.read(200)), "剛收車（pending）不是 uncertain")
nowMs = t0 + Store.SETTLE_MS - 1
Store.settleDue(nowMs)
check(Store.read(200).settled == nil, "未滿 5 秒不寫 settled")
nowMs = t0 + Store.SETTLE_MS
quiet = true
Store.settleDue(nowMs)
quiet = false
check(Store.read(200).settled == true and not Store.uncertain(200, Store.read(200)), "滿 5 秒寫上 settled（含讀回）")
Store.write(201, { state = "UNPACKED", history = {} })
local logBefore = #logLines
quiet = true
check(Store.uncertain(201, Store.read(201)), "沒有 settled 又不在 pending＝uncertain（當機留下的）")
Store.read(201)
quiet = false
local warns = 0
for i = logBefore + 1, #logLines do
    if logLines[i]:find("UNCERTAIN capsule=201", 1, true) then warns = warns + 1 end
end
check(warns == 1, "開服後第一次讀到 uncertain 寫一行 log，之後不重複（" .. warns .. "）")
Store.write(202, { state = "PACKED", history = {} })
Store.schedule(202)
dropWrites, quiet = true, true
nowMs = nowMs + Store.SETTLE_MS
Store.settleDue(nowMs)
dropWrites, quiet = false, false
check(Store.read(202).settled == nil and Store.uncertain(202, Store.read(202)), "settle 寫不進去：離開 pending，變 uncertain")
check(Store.uncertain(203, { state = "VOID" }) == false, "VOID 不算 uncertain")

-- history: PACKED with the original car 7 at (1, 2); UNPACKED/RESTORED add the new car 8 at (x or 1, 2)
local function rec(id, state, settled, x)
    local h = { { ev = "PACKED", car = 7, x = 1, y = 2, z = 0 } }
    if state ~= "PACKED" then h[2] = { ev = state, car = 8, x = x or 1, y = 2, z = 0 } elseif x then h[1].x = x end
    Store.write(id, { state = state, settled = settled, script = "Base.PickUpTruck",
        manifest = { ["Base.WaterBottle"] = 2 }, history = h })
end

print("Store.claim：只接受 PACKED 且不是 uncertain；舊膠囊依狀態處理")
quiet = true
local claimCases = {
    { 301, "PACKED", true, nil }, { 302, "PACKED", nil, "UNCERTAIN" }, { 303, "UNPACKED", nil, "UNCERTAIN" },
    { 304, "UNPACKED", true, "STALE" }, { 305, "VOID", nil, "STALE" }, { 306, "RESTORED", true, "NOT_PACKED" },
}
local claimResults = {}
for _, c in ipairs(claimCases) do
    rec(c[1], c[2], c[3])
    local s, w, stale = Store.claim(c[1], player)
    local after = Store.read(c[1])
    local ev = after.history[#after.history]
    local good
    if c[4] == nil then
        good = s ~= nil and after.state == "UNPACKED"
    elseif c[4] == "STALE" then
        good = s == nil and w == "STALE" and stale ~= nil and after.state == c[2] and ev.ev ~= "REJECTED"
    else
        good = s == nil and w == c[4] and after.state == c[2] and ev.ev == "REJECTED" and ev.why == c[4]
    end
    claimResults[#claimResults + 1] = { good, c[2] .. (c[3] and "+settled" or "+unsettled") .. " -> "
        .. tostring(c[4] or "UNPACKED") .. "（得到 " .. tostring(w or (s and s.state)) .. "）" }
end
rec(307, "PACKED", nil)
Store.schedule(307)
local quick = Store.claim(307, player)
quiet = false
for _, cr in ipairs(claimResults) do check(cr[1], cr[2]) end
check(quick ~= nil, "同一次開服收車後馬上展開（pending）照常成功")

print("Admin.resolve：只處理 uncertain，分支照判定")
local admin, nobody = newPlayer("admin", true), newPlayer("bob", false)
loadedSquares["1,2"] = {}
local function resolve(id, verdict, checked) return Admin.resolve(admin, id, verdict, "note", checked) end
quiet = true
rec(401, "PACKED", nil)
local rNo = Admin.resolve(nobody, 401, "present")
rec(402, "PACKED", true)
local rSettled = resolve(402, "present")
loadedCars = { fakeCar(7) }
local r401 = resolve(401, "present")
local s401 = Store.read(401)
rec(403, "PACKED", nil)
local r403exists = resolve(403, "missing")
loadedCars = {}
local r403site = resolve(403, "present")
local r403checked = resolve(403, "present", true)
rec(404, "PACKED", nil)
local r404 = resolve(404, "missing")
rec(405, "UNPACKED", nil)
loadedCars = { fakeCar(7) } -- only the original car is loaded; the record's car is the new one (8)
local r405 = resolve(405, "missing")
local s405 = Store.read(405)
local claim405 = Store.claim(405, player)
loadedCars = { fakeCar(8) }
rec(406, "UNPACKED", nil)
local r406 = resolve(406, "present")
loadedCars = {}
rec(407, "PACKED", nil, 900)
local r407 = resolve(407, "missing")
local r407checked = resolve(407, "missing", true)
rec(408, "PACKED", nil)
local r408 = resolve(408, "maybe")
loadedCars = { fakeCar(7, "Base.CarNormal") } -- sqlId reused by another model after a crash
rec(409, "PACKED", nil)
local r409 = resolve(409, "missing")
loadedCars = {}
quiet = false
check(rNo.why == "NOT_ADMIN", "非管理員 NOT_ADMIN")
check(rSettled.why == "NOT_UNCERTAIN", "已落盤的紀錄不必判定 NOT_UNCERTAIN")
check(r401.ok and s401.state == "VOID" and s401.history[#s401.history].ev == "RESOLVED"
    and s401.history[#s401.history].verdict == "present", "PACKED＋原車找得到，判「車在」-> VOID，記 RESOLVED")
check(r403exists.why == "CAR_EXISTS", "伺服器找得到車時「車不在」被拒 CAR_EXISTS")
check(r403site.why == "CHECK_SITE", "找不到車又沒到現場確認，「車在」-> CHECK_SITE")
check(r403checked.ok and Store.read(403).state == "VOID", "到現場確認車在 -> VOID")
check(r404.ok and Store.read(404).state == "PACKED" and Store.read(404).settled == true, "PACKED＋車不在 -> 寫上 settled（照常可補回）")
check(r405.ok and s405.state == "PACKED" and s405.settled == true, "UNPACKED＋新車不在 -> 改回 PACKED 並 settled")
check(claim405 ~= nil, "改回 PACKED 後玩家可以再丟一次")
check(r406.ok and Store.isStale(Store.read(406)), "UNPACKED＋新車在 -> settled，舊膠囊之後會被清空")
check(r407.why == "CHECK_SITE" and r407checked.ok, "紀錄位置沒載入：「車不在」要 checked")
check(r408.why == "BAD_ARGS", "不認得的判定 BAD_ARGS")
check(r409.ok, "同 sqlId 但車種不同（sqlId 被重用）不算紀錄的車")

print("Admin.restore：可補的狀態、CAR_EXISTS、checked、先改 RESTORED 再生車")
local spawnFails, restoringId, fileAtSpawn = false, nil, {}
M.Unpack.spawn = function(s)
    fileAtSpawn[restoringId] = s.state .. "/" .. tostring(Store.read(restoringId).state)
    if spawnFails then return nil, "BLOCKED" end
    local sq = { getX = function() return 1 end, getY = function() return 2 end, getZ = function() return 0 end }
    return { getSquare = function() return sq end, getSqlId = function() return 99 end, getId = function() return 5 end }, {}
end
local function restore(id, x, checked)
    restoringId = id
    return Admin.restore(admin, id, x or 1, 2, 0, "gave water back", checked)
end
quiet = true
local notRestorable = {}
for id, st in pairs({ [501] = { "VOID", true }, [502] = { "RESTORED", true }, [503] = { "UNPACKED", true } }) do
    rec(id, st[1], st[2])
    notRestorable[#notRestorable + 1] = restore(id, 1, true).why
end
rec(504, "PACKED", true)
loadedCars = { fakeCar(7) }
local r504 = restore(504)
loadedCars = {}
rec(505, "PACKED", nil)
local r505 = restore(505)
local r505checked = restore(505, 1, true)
rec(506, "PACKED", true)
local r506 = restore(506)
local s506 = Store.read(506)
local claim506, why506 = Store.claim(506, player)
rec(507, "UNPACKED", nil)
local r507 = restore(507, 1, true)
rec(508, "UNPACKED", nil)
spawnFails = true
local r508 = restore(508, 1, true)
spawnFails = false
nowMs = nowMs + Store.SETTLE_MS
Store.settleDue(nowMs)
local s508 = Store.read(508)
rec(509, "PACKED", true)
local r509 = restore(509, 900)
quiet = false
check(table.concat(notRestorable, ",") == "NOT_RESTORABLE,NOT_RESTORABLE,NOT_RESTORABLE", "VOID、RESTORED、已落盤 UNPACKED 不能補：" .. table.concat(notRestorable, ","))
check(r504.why == "CAR_EXISTS", "紀錄的車找得到 -> CAR_EXISTS")
check(r505.why == "CHECK_SITE" and r505checked.ok, "uncertain 的 PACKED 要 checked 才補")
check(r506.ok and r506.sqlId == 99 and fileAtSpawn[506] == "RESTORED/RESTORED", "生車時快照與檔案已是 RESTORED（" .. tostring(fileAtSpawn[506]) .. "）")
local last506 = s506.history[#s506.history]
check(last506.ev == "RESTORED" and last506.car == 99 and last506.note == "gave water back" and last506.items == "Base.WaterBottle*2"
    and s506.history[#s506.history - 1].ev == "RESTORE_START", "記 RESTORE_START、RESTORED（新車、備註、貨物清單）")
check(claim506 == nil and why506 == "NOT_PACKED", "補回後原膠囊不能再展開")
check(r507.ok and Store.read(507).state == "RESTORED", "uncertain 的 UNPACKED 確認後可補")
check(r508.why == "BLOCKED" and s508.state == "UNPACKED" and s508.settled == nil and Store.uncertain(508, s508)
    and s508.history[#s508.history].ev == "RESTORE_FAILED", "生車失敗退回原狀態，仍是 uncertain（不會被 settle）")
check(r509.why == "BLOCKED" and Store.read(509).state == "PACKED", "補回位置沒載入 -> BLOCKED，不動狀態")

print("Guard：清空規則（哪些狀態清、哪些不動）與貨物鎖")
local owner = newPlayer("owner", false)
local function packedCapsule(state, settled)
    local cap = instanceItem(M.ITEM_LOADED)
    local water, bag, pencil = newItem("Base.WaterBottle"), newItem("Base.Bag_Schoolbag", true), newItem("Base.Pencil")
    cap.inv:AddItem(water)
    cap.inv:AddItem(bag)
    bag.inv:AddItem(pencil)
    owner.inv:AddItem(cap)
    Store.write(cap.id, { state = state, settled = settled, script = "Base.PickUpTruck",
        sealed = { water.id, bag.id, pencil.id }, history = { { ev = "PACKED", car = 7 } } })
    return cap, water, bag, pencil
end
local function topLevel(type)
    local n = 0
    for _, x in ipairs(owner.inv.list) do if x.type == type then n = n + 1 end end
    return n
end
local clearCases = {
    { "UNPACKED", true, true }, { "VOID", nil, true },
    { "PACKED", nil, false }, { "UNPACKED", nil, false }, { "RESTORED", true, false }, { "PACKED", true, false },
}
quiet = true
local clearResults = {}
for _, c in ipairs(clearCases) do
    local cap = packedCapsule(c[1], c[2])
    local empties = topLevel(M.ITEM_EMPTY)
    Guard.pass(owner)
    local gone = owner.inv:getItemWithIDRecursiv(cap.id) == nil
    local h = Store.read(cap.id).history
    local cleared = gone and topLevel(M.ITEM_EMPTY) == empties + 1 and h[#h].ev == "CLEARED"
        and h[#h].items:find("Base.Pencil*1", 1, true) ~= nil
    clearResults[#clearResults + 1] = { (c[3] and cleared) or (not c[3] and not gone and h[#h].ev ~= "CLEARED"),
        c[1] .. (c[2] and "+settled" or "+unsettled") .. (c[3] and " -> 換成空膠囊、記 CLEARED 與貨物" or " -> 不動") }
    if not gone then owner.inv:Remove(cap) end
end
local stale = packedCapsule("UNPACKED", true)
local unpackRes = M.Unpack.unpack(owner, stale, nil, "N")
local staleGone = owner.inv:getItemWithIDRecursiv(stale.id) == nil
local cap, water, bag, pencil = packedCapsule("PACKED", true)
cap.inv:Remove(water)
owner.inv:AddItem(water)
cap.inv:Remove(bag)
owner.inv:AddItem(bag)
Guard.pass(owner)
local lockH = Store.read(cap.id).history
cap.inv:Remove(water)
owner.inv:AddItem(water)
water.equipped = true
Guard.pass(owner)
Guard.pass(owner)
local missing = 0
for _, e in ipairs(Store.read(cap.id).history) do if e.why == "missing" then missing = missing + 1 end end
quiet = false
for _, cr in ipairs(clearResults) do check(cr[1], cr[2]) end
check(unpackRes.why == "CLEARED" and staleGone, "展開時遇到已落盤的 UNPACKED：拒絕並清空（CLEARED）")
check(bag.container == cap.inv and pencil.container == bag.inv and topLevel("Base.Bag_Schoolbag") == 0,
    "搬出的背包連同裡面的鉛筆放回膠囊，玩家身上不留")
local lockEv = lockH[#lockH]
check(lockEv.ev == "CARGO_LOCK" and lockEv.why == "returned" and lockEv.items:find("Base.WaterBottle", 1, true) ~= nil
    and lockEv.items:find("Base.Bag_Schoolbag", 1, true) ~= nil, "記 CARGO_LOCK returned（水瓶、背包）：" .. tostring(lockEv.items))
check(water.container == owner.inv and missing == 1, "裝備中的物品不硬拿，只記一次 missing")

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
