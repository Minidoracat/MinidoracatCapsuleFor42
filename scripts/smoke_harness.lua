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
function getWorld() return { getWorld = function() return "harness world" end } end
-- 全域 ModData（跟世界存檔一起存）：Store 的展開標記；ModData.tables 讓測試看得到、也能清掉模擬回溯
ModData = { tables = {} }
function ModData.getOrCreate(key)
    ModData.tables[key] = ModData.tables[key] or {}
    return ModData.tables[key]
end

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
check(Store.dir() == "MinidoracatVehicleCapsule/MP_harness_world/" and files[Store.path(42, "a")] ~= nil
    and files[Store.path(42, "a")]:find("\n42 {", 1, true) ~= nil, "落在這個世界的資料夾、42 號桶的 a 份（MP_<伺服器>）")
local r = Store.read(42)
check(r and diff(snap, r) == nil, "read 讀回與寫入相同")
check(select(2, Store.read(43)) == "NO_SNAPSHOT", "沒有檔案回 NO_SNAPSHOT")
files[Store.path(44, "a")] = "MVC1 1\n44 {broken\nEND 1 1" -- 桶檔完整，只有這一筆壞掉
check(select(2, Store.read(44)) == "CORRUPT", "壞掉的一筆回 CORRUPT")
Store.write(45, { state = "PACKED", settled = true, history = {} })
check(Store.claim(45, player) ~= nil and Store.marked(45) and Store.release(45, Store.read(45), player, "x") == true
    and not Store.marked(45), "claim 在 ModData 標記展開，生車失敗退回 PACKED 時拿掉標記")

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
check(files[Store.path(62, "a")] == nil and files[Store.path(62, "b")] == nil, "被拒時不寫桶檔")

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
local placed = Store.recordedCar({ history = {
    { ev = "PACKED", x = 10, y = 10, z = 0, car = 7 },
    { ev = "RESOLVED", verdict = "missing", x = 20, y = 20, z = 0, car = 7 },
} })
check(placed.ev == "PACKED" and placed.x == 10 and placed.y == 10,
    "紀錄位置取最後一次放車的事件，判定（RESOLVED）時管理員站的位置不算")

print("Unpack.spawn：快照缺欄位時不生車（CORRUPT）")
local spawnedCount = 0
local savedAdd = addVehicleDebug
addVehicleDebug = function() spawnedCount = spawnedCount + 1; return nil end
local fullSnap = { script = "Base.PickUpTruck", keyId = 1, rust = 0, parts = {}, hsv = { 0.1, 0.2, 0.3 }, engine = { 50, 40, 60 } }
check(M.Snapshot.missing(fullSnap) == nil, "完整的快照沒有缺欄位")
local brokenHsv = Json.copy(fullSnap); brokenHsv.hsv = { 0.1, 0.2 }
local noEngine = Json.copy(fullSnap); noEngine.engine = nil
local noKey = Json.copy(fullSnap); noKey.keyId = nil
check(M.Snapshot.missing(brokenHsv) == "hsv" and M.Snapshot.missing(noEngine) == "engine"
    and M.Snapshot.missing(noKey) == "keyId", "缺 hsv／engine／keyId 各自指出欄位")
quiet = true
local v1, why1 = M.Unpack.spawn(brokenHsv, {}, "N")
quiet = false
check(v1 == nil and why1 == "CORRUPT" and spawnedCount == 0, "缺欄位的快照回 CORRUPT，而且沒有呼叫 addVehicleDebug")
do -- SP 在 addVehicleDebug 裡同步跑 damnlib 客戶端 Init：空槽的隨機補件要停掉，生完再換回原函式
    local damnCalls, savedDirs = 0, IsoDirections
    IsoDirections = { N = "N" }
    local damnDefaults = function() damnCalls = damnCalls + 1 end
    DAMN = { Parts = { processDefaults = damnDefaults } }
    addVehicleDebug = function() DAMN.Parts:processDefaults(); return nil end
    local v2, why2 = M.Unpack.spawn(fullSnap, {}, "N")
    check(v2 == nil and why2 == "BLOCKED" and damnCalls == 0 and DAMN.Parts.processDefaults == damnDefaults,
        "addVehicleDebug 期間 damnlib 的空槽隨機補件不動作，之後換回原函式")
    DAMN, IsoDirections = nil, savedDirs
end
addVehicleDebug = savedAdd

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
-- { state, settled, cleared?, marked? }：marked＝世界存檔已知道這次展開（ModData 標記）
local clearCases = {
    { "UNPACKED", true, true, true }, { "VOID", nil, true },
    { "PACKED", nil, false }, { "UNPACKED", nil, false }, { "RESTORED", true, false }, { "PACKED", true, false },
}
quiet = true
local clearResults = {}
for _, c in ipairs(clearCases) do
    local cap = packedCapsule(c[1], c[2])
    if c[4] then Store.mark(cap.id) end
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
Store.mark(stale.id)
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

do -- 拿出模式（AllowCargoTakeOut）：主程式的 local 已接近 200 個上限，放進函式
    (function()
        print("Guard：伺服器允許拿出貨物時，跟著紀錄、不放回；沒落盤的照樣放回")
        owner.inv:Remove(cap) -- 上面貨物鎖那顆（水瓶裝備中）不參與
        SandboxVars = { MinidoracatVehicleCapsule = { AllowCargoTakeOut = true } }
        quiet = true
        local open, water, bag, pencil = packedCapsule("PACKED", true)
        local s0 = Store.read(open.id)
        s0.manifest = { ["Base.WaterBottle"] = 1, ["Base.Bag_Schoolbag"] = 1 }
        Store.write(open.id, s0)
        open.inv:Remove(water)
        owner.inv:AddItem(water)
        bag.inv:Remove(pencil)
        owner.inv:AddItem(pencil)
        Guard.pass(owner)
        Guard.pass(owner)
        local s1 = Store.read(open.id)
        local taken = 0
        for _, e in ipairs(s1.history) do if e.ev == "CARGO_TAKEN" then taken = taken + 1 end end
        local last = s1.history[#s1.history]
        owner.inv:Remove(open)
        local settling, water2 = packedCapsule("PACKED", nil)
        settling.inv:Remove(water2)
        owner.inv:AddItem(water2)
        Guard.pass(owner)
        local h2 = Store.read(settling.id).history
        owner.inv:Remove(settling)
        local R = M.Rules
        local only = R.cargoOpen({ state = "PACKED", settled = true }) and not R.cargoOpen({ state = "PACKED", settled = false })
            and not R.cargoOpen({ state = "UNPACKED", settled = true }) and not R.cargoOpen({ state = "VOID", settled = true })
            and not R.cargoOpen(nil)
        SandboxVars = nil
        local off = not R.cargoOpen({ state = "PACKED", settled = true })
        quiet = false
        check(water.container == owner.inv and pencil.container == owner.inv,
            "已落盤的膠囊：拿出的水瓶、背包裡拿出的鉛筆都留在玩家身上")
        check(#s1.sealed == 1 and s1.sealed[1] == bag.id and s1.manifest["Base.Bag_Schoolbag"] == 1
            and s1.manifest["Base.WaterBottle"] == nil, "紀錄只剩還在膠囊裡的背包（sealed、manifest）")
        check(taken == 1 and last.ev == "CARGO_TAKEN" and last.items:find("Base.WaterBottle*1", 1, true) ~= nil
            and last.items:find("Base.Pencil*1", 1, true) ~= nil, "記一次 CARGO_TAKEN（水瓶、鉛筆），第二輪不重記：" .. tostring(last.items))
        check(water2.container == settling.inv and h2[#h2].ev == "CARGO_LOCK" and h2[#h2].why == "returned",
            "剛收好、還沒落盤的膠囊照樣放回（CARGO_LOCK returned）")
        check(only and off, "Rules.cargoOpen：只有已落盤的 PACKED，而且沙盒開著")
    end)()
end

do -- 回溯判斷：主程式的 local 已接近 200 個上限，放進函式
    (function()
        print("Guard.stale：世界存檔比展開舊（沒有 ModData 標記）時，車在才清空，車不在交給管理員")
        local function unpackedTo(car)
            local c = packedCapsule("UNPACKED", true)
            local s = Store.read(c.id)
            s.history[#s.history + 1] = { ev = "UNPACKED", car = car, x = 1, y = 1, z = 0 }
            Store.write(c.id, s)
            return c
        end
        quiet = true
        local lost = unpackedTo(4242) -- 車跟著世界回溯不見了
        Guard.pass(owner)
        local afterLost = Store.read(lost.id)
        local keptLost = owner.inv:getItemWithIDRecursiv(lost.id) ~= nil
        owner.inv:Remove(lost)
        local here = unpackedTo(4343) -- 當機：車已寫進 vehicles.db，膠囊跟著玩家存檔回來
        loadedCars[#loadedCars + 1] = fakeCar(4343)
        Guard.pass(owner)
        local hereGone = owner.inv:getItemWithIDRecursiv(here.id) == nil
        local hh = Store.read(here.id).history
        local thrown = unpackedTo(4444)
        local res = M.Unpack.unpack(owner, thrown, nil, "N")
        local thrownKept = owner.inv:getItemWithIDRecursiv(thrown.id) ~= nil
        owner.inv:Remove(thrown)
        local resolved = Admin.resolve(newPlayer("adm", true), thrown.id, "present", nil, true)
        quiet = false
        check(keptLost and afterLost.settled == nil and Store.uncertain(lost.id, afterLost)
            and afterLost.history[#afterLost.history].ev == "SUSPECT", "車不在：膠囊不動，紀錄改回當機前未確認（SUSPECT）")
        check(hereGone and hh[#hh].ev == "CLEARED" and Store.marked(here.id), "車在：清空重複的貨物並補上標記")
        check(res.ok == false and res.why == "UNCERTAIN" and thrownKept, "丟出時遇到同樣情況：拒絕（UNCERTAIN），膠囊不動")
        check(resolved.ok and Store.marked(thrown.id), "管理員判定「車在」後補上標記，下一輪照常清空")
    end)()
end

-- ===== Phase 3：落點範圍、收車權限、玩家身分（intent） =====
require "MinidoracatVehicleCapsule/Footprint"
require "MinidoracatVehicleCapsule/Rules"
local clientCommand
Events.OnClientCommand = { Add = function(fn) clientCommand = fn end }
require "MinidoracatVehicleCapsule/PlayerCommands"
local Footprint, Rules, Play = M.Footprint, M.Rules, M.Play

print("Footprint：方向與範圍")
check(Footprint.dirOf(5, 1) == "E" and Footprint.dirOf(-5, 1) == "W" and Footprint.dirOf(1, 6) == "S"
    and Footprint.dirOf(0, -3) == "N" and Footprint.dirOf(3, 3) == "E", "丟出方向取最近的東南西北")
-- 車身繞中心最多偏 0.2 rad（addVehicleDebug）：四角在各角度都要落在 box 內
local function bodyInside(x, y, dir, w, l)
    local b = Footprint.box(x, y, dir, w, l)
    local base = ({ N = 0, S = 0, E = math.pi / 2, W = math.pi / 2 })[dir]
    for _, da in ipairs({ -0.2, -0.1, 0, 0.1, 0.2 }) do
        local a = base + da
        for _, c in ipairs({ { -1, -1 }, { -1, 1 }, { 1, -1 }, { 1, 1 } }) do
            local lx, ly = c[1] * w / 2, c[2] * l / 2 -- 寬沿 x、長沿 y（朝北）
            local px = x + lx * math.cos(a) - ly * math.sin(a)
            local py = y + lx * math.sin(a) + ly * math.cos(a)
            local tx, ty = math.floor(px), math.floor(py)
            if tx < b.x1 or tx > b.x2 or ty < b.y1 or ty > b.y2 then return false, b end
        end
    end
    return true, b
end
local inN, bN = bodyInside(10, 20, "N", 2.2, 5.0)
local inE, bE = bodyInside(10, 20, "E", 2.2, 5.0)
check(inN and inE, "皮卡（2.2×5）朝北／朝東轉 ±0.2 rad，四角都在 box 內")
check(bN.y2 - bN.y1 > bN.x2 - bN.x1 and bE.x2 - bE.x1 > bE.y2 - bE.y1, "朝北長邊沿 y、朝東長邊沿 x")

-- 假格子：預設空曠的戶外地面
IsoFlagType = { solidfloor = "solidfloor" }
for k in pairs(loadedSquares) do loadedSquares[k] = nil end
local function fakeSquare(x, y)
    local s = { x = x, y = y, free = true, floor = true, outside = true, wallE = false, wallS = false }
    function s:getX() return self.x end
    function s:getY() return self.y end
    function s:getZ() return 0 end
    function s:getVehicleContainer() return self.vehicle end
    function s:getMovingObjects() return javaList(self.movers or {}) end
    function s:isFree() return self.free and self.floor and not self.tree end
    function s:HasTree() return self.tree == true end
    function s:has(flag) return flag == "solidfloor" and self.floor end
    function s:isOutside() return self.outside end
    function s:isBlockedTo(o)
        if o.x == self.x + 1 then return self.wallE end
        if o.y == self.y + 1 then return self.wallS end
        return false
    end
    loadedSquares[x .. "," .. y] = s
    return s
end
for x = 0, 30 do for y = 0, 40 do fakeSquare(x, y) end end
local function sq(x, y) return loadedSquares[x .. "," .. y] end
local function getSq(x, y) return sq(x, y) end
local pickup = { getExtents = function() return { x = function() return 2.2 end, z = function() return 5.0 end } end }
local function clearAt(x, y, dir) return (Footprint.clear(pickup, x, y, 0, dir or "N")) end
check(clearAt(10, 20) == nil, "空地：放得下")
local function blockedBy(setup, undo, want, label)
    setup()
    local got = clearAt(10, 20)
    undo()
    check(got == want, label .. "（得到 " .. tostring(got) .. "）")
end
blockedBy(function() sq(9, 18).tree = true end, function() sq(9, 18).tree = nil end, "TREE", "車身範圍內有樹")
blockedBy(function() sq(10, 22).free = false end, function() sq(10, 22).free = true end, "SOLID", "車身範圍內有家具")
blockedBy(function() sq(11, 17).floor = false end, function() sq(11, 17).floor = true end, "NO_FLOOR", "沒有地面（水）")
blockedBy(function() sq(8, 22).vehicle = {} end, function() sq(8, 22).vehicle = nil end, "VEHICLE", "另一台車壓到範圍")
blockedBy(function() sq(10, 17).movers = { {} } end, function() sq(10, 17).movers = nil end, "PERSON", "範圍內有人或殭屍")
blockedBy(function() sq(10, 16).movers = { {} } end, function() sq(10, 16).movers = nil end, nil, "車頭前一格的人不算")
blockedBy(function() sq(9, 20).wallE = true end, function() sq(9, 20).wallE = false end, "WALL", "範圍內兩格之間有牆或圍欄")
blockedBy(function() sq(11, 20).wallE = true end, function() sq(11, 20).wallE = false end, nil, "範圍外緣的牆不算（不擋車身）")
blockedBy(function() sq(10, 20).outside = false end, function() sq(10, 20).outside = true end, "INDOORS", "中心在室內")
blockedBy(function() loadedSquares["12,21"] = nil end, function() fakeSquare(12, 21) end, nil, "範圍外的格子沒載入不影響")
blockedBy(function() loadedSquares["11,21"] = nil end, function() fakeSquare(11, 21) end, "UNLOADED", "範圍內的格子沒載入")
check(Footprint.blocked(getSq, Footprint.box(10, 20, "E", 2.2, 5.0), 0) == nil, "朝東也放得下")
-- 按按鈕：玩家站在膠囊旁邊，車放在另一側 3 格（中心＝落點格的西北角），玩家那一格不能在範圍內
local pb = Footprint.box(23, 30, "E", 2.2, 5.0)
check(pb.x1 >= 20, "膠囊在 (20,30)、往東 3 格放車：站在膠囊西邊 (19,30) 的玩家不在範圍內（x1=" .. pb.x1 .. "）")

print("Footprint：丟擲距離與視線")
local losBlocked = false
LosUtil = { lineClear = function() return losBlocked and "Blocked" or "Clear" end }
check(Footprint.reach(10.5, 10.5, 0, 17, 10, 0, 8, true) == nil, "7 格、看得到：可以丟")
check(Footprint.reach(10.5, 10.5, 0, 19, 10, 0, 8, true) == "TOO_FAR", "8.5 格：太遠")
check(Footprint.reach(10.5, 10.5, 1, 15, 10, 0, 8, true) == "TOO_FAR", "不同樓層：不行")
losBlocked = true
check(Footprint.reach(10.5, 10.5, 0, 15, 10, 0, 8, true) == "NO_SIGHT", "視線被擋：看不到")
check(Footprint.reach(10.5, 10.5, 0, 12, 10, 0, 3, false) == nil, "按按鈕不看視線，只看 3 格內")
losBlocked = false

print("Rules：膠囊名稱、收車權限")
check(Rules.cleanName("  Vehicle Capsule: [b]Car\n\1<RGB:1,0,0>  ") == "Vehicle Capsule: bCarRGB:1,0,0",
    "清掉控制字元、[ ]、< >，去頭尾空白：" .. tostring(Rules.cleanName("  Vehicle Capsule: [b]Car\n\1<RGB:1,0,0>  ")))
check(#Rules.cleanName(string.rep("a", 200)) == Rules.NAME_MAX, "名稱最長 64")
check(Rules.cleanName(" \n ") == nil and Rules.cleanName(nil) == nil and Rules.cleanName(5) == nil, "空的或不是字串：退回伺服器組字")
local car = { keyId = 4242, ignition = false }
function car:getKeyId() return self.keyId end
function car:isKeysInIgnition() return self.ignition end
function car:getCurrentKey() return nil end
local keyHolder, stranger, admin3 = newPlayer("keyholder", false), newPlayer("stranger", false), newPlayer("boss", true)
keyHolder.inv.haveThisKeyId = function(_, id) return id == 4242 and {} or nil end
stranger.inv.haveThisKeyId = function() return nil end
admin3.inv.haveThisKeyId = function() return nil end
SandboxVars = { MinidoracatVehicleCapsule = { PackPermission = 1 } }
check(Rules.mayPack(keyHolder, car) and not Rules.mayPack(stranger, car), "模式 1：有鑰匙才行（背包）")
check(Rules.mayPack(admin3, car) and select(2, Rules.mayPack(admin3, car)) == "ADMIN", "模式 1：管理員沒鑰匙也能收")
SandboxVars.MinidoracatVehicleCapsule.PackPermission = 3
check(not Rules.mayPack(stranger, car) and not Rules.mayPack(keyHolder, car), "模式 3：有鑰匙的一般玩家也不行")
do -- VehicleManager 假實作：照玩家回答，記下問的是哪個權限（收車＝拖曳 TOW）
    local vmAsked
    local function vmStub(answers)
        return { canUse = function(p, _, action)
            vmAsked = action
            local a = answers[p] or { false, "NOT_AUTHORIZED" }
            return a[1], a[2]
        end }
    end
    MinidoracatVehicleManagerAPI = vmStub({})
    check(not Rules.mayPack(admin3, car) and vmAsked == "TOW", "VehicleManager 綁定的車：問拖曳權限；管理員沒開越權也不行")
    MinidoracatVehicleManagerAPI = nil
    SandboxVars.MinidoracatVehicleCapsule.PackPermission = 1
    car.ignition = true
    check(Rules.mayPack(stranger, car), "模式 1：鑰匙插在點火孔，誰都能收")
    car.ignition = false
    SandboxVars.MinidoracatVehicleCapsule.PackPermission = 2
    check(Rules.mayPack(stranger, car), "模式 2：任何人")
    SandboxVars.MinidoracatVehicleCapsule.PackPermission = 3
    check(Rules.mayPack(admin3, car) and not Rules.mayPack(keyHolder, car), "模式 3：只有管理員")
    MinidoracatVehicleManagerAPI = vmStub({ [stranger] = { true, "OWNER" }, [keyHolder] = { true, "MEMBER" },
        [admin3] = { false, "RENT_LOCKED" } })
    local ownOk, ownMode = Rules.mayPack(stranger, car)
    local shOk, shMode = Rules.mayPack(keyHolder, car)
    local lkOk, lkMode, lkWhy = Rules.mayPack(admin3, car)
    check(ownOk and ownMode == "VM" and shOk and shMode == "SHARED",
        "VehicleManager 綁定的車：車主與被分享拖曳的人都能收（模式 3 的沙盒不看）")
    check(not lkOk and lkMode == "VM" and lkWhy == "RENT_LOCKED", "VehicleManager 擋下時帶回它的原因（租用到期鎖定）")
    MinidoracatVehicleManagerAPI = vmStub({ [admin3] = { true, "ADMIN" } })
    local ovOk, ovMode = Rules.mayPack(admin3, car)
    check(ovOk and ovMode == "ADMIN" and not Rules.mayPack(keyHolder, car),
        "VehicleManager 越權中的管理員算「管理員」；別人綁定的車，有鑰匙也不行")
    MinidoracatVehicleManagerAPI = { canUse = function() return true, "UNCLAIMED" end }
    SandboxVars.MinidoracatVehicleCapsule.PackPermission = 1
    local unOk, unMode = Rules.mayPack(admin3, car)
    check(Rules.mayPack(keyHolder, car) and not Rules.mayPack(stranger, car) and unOk and unMode == "ADMIN",
        "VehicleManager 沒綁定的車照沙盒：模式 1 要鑰匙，管理員照常")
    MinidoracatVehicleManagerAPI = nil
    SandboxVars = nil
end

print("Play：身分只認 OnClientCommand 的連線（intent）")
local alice, bob = newPlayer("alice", false), newPlayer("bob", false)
clientCommand(M.MODULE, "intent", alice, { kind = "pack", id = 77, name = "[x]Car\n" })
clientCommand(M.MODULE, "intent", alice, { kind = "nuke", id = 77 })
check(Play.takeIntent(bob, "pack", 77) == nil, "別人的 intent 不能拿來用（bob 冒充 alice 的車）")
local it = Play.takeIntent(alice, "pack", 77)
check(it ~= nil and it.name == "xCar", "同一連線的 intent 可用，名稱已清理：" .. tostring(it and it.name))
check(Play.takeIntent(alice, "pack", 77) == nil, "intent 用一次就沒了")
check(Play.takeIntent(alice, "nuke", 77) == nil, "不認得的種類不收")
clientCommand(M.MODULE, "intent", alice, { kind = "throw", id = 9 })
nowMs = nowMs + 61000
check(not Play.hasIntent(alice, "throw", 9), "60 秒後過期")
logLines = {}
local printed, savedPrint = {}, print
alice.inv.containsID = function() return false end
print = function(s) printed[#printed + 1] = tostring(s) end
local refused = Play.pack(alice, { getId = function() return 77 end }, "local")
local thrown = Play.throw({ character = alice, item = { getID = function() return 5 end,
    getFullType = function() return M.ITEM_LOADED end }, x = 1, y = 1, z = 0 })
print = savedPrint
check(refused == false and printed[1] and printed[1]:find("pack refused by=alice why=NO_INTENT", 1, true) ~= nil,
    "沒有 intent 的收車被拒並記一行：" .. tostring(printed[1]))
check(thrown == false, "膠囊不在背包裡的丟擲被拒")
-- ===== Phase 4：索引分頁、查詢權限、管理指令、戰利品權重 =====
-- 新的假全域：原生沙盒選項、server->client 指令
local sandbox = {}
function getSandboxOptions()
    return { getOptionByName = function(_, name)
        local k = name:match("^MinidoracatVehicleCapsule%.(.+)$")
        if k == nil or sandbox[k] == nil then return nil end
        return { getValue = function() return sandbox[k] end }
    end }
end
local sent = {}
function sendServerCommand(...) sent[#sent + 1] = { ... } end

-- 把舊情境的紀錄清掉，Phase 4 從空的桶開始（Store 對桶檔的快取一起清）
for path in pairs(files) do files[path] = nil end
Store._resetForTests()
require "MinidoracatVehicleCapsule/Index"
require "MinidoracatVehicleCapsule/Query"
require "MinidoracatVehicleCapsule/AdminCommands"
require "MinidoracatVehicleCapsule/Loot"
local Index, Query, AdminCommands, Loot = M.Index, M.Query, M.AdminCommands, M.Loot

print("Index：分頁 50 筆、搜尋編號與玩家、狀態篩選（含當機前未確認）")
-- 65 筆：60 筆 PACKED（玩家 p0..p5 輪流收）、2 筆 UNPACKED（ann 展開）、1 筆 RESTORED、1 筆 VOID、1 筆 uncertain
quiet = true
local base = nowMs
for i = 1, 60 do
    Store.write(70000 + i, { state = "PACKED", settled = true, script = "Base.PickUpTruck", name = "Pickup", packedBy = "P" .. (i % 6),
        history = { { t = base + i, ev = "PACKED", by = "P" .. (i % 6), x = i, y = 2, z = 0, car = i } } })
end
for i = 61, 62 do
    Store.write(70000 + i, { state = "UNPACKED", settled = true, packedBy = "p1", history = {
        { t = base + i, ev = "PACKED", by = "p1", car = i }, { t = base + 100 + i, ev = "UNPACKED", by = "Ann", car = 900 + i } } })
end
Store.write(70063, { state = "RESTORED", settled = true, packedBy = "p2", history = { { t = base + 63, ev = "PACKED", by = "p2" } } })
Store.write(70064, { state = "VOID", settled = true, packedBy = "p3", history = { { t = base + 64, ev = "PACKED", by = "p3" } } })
Store.write(70065, { state = "PACKED", packedBy = "p4", history = { { t = base + 65, ev = "PACKED", by = "p4" } } }) -- 沒有 settled＝uncertain
quiet = false
local p1 = Index.page({}, 1)
local p2 = Index.page({}, 2)
check(#p1.rows == 50 and p1.total == 65 and p1.pages == 2 and #p2.rows == 15, "65 筆分成 50＋15（" .. #p1.rows .. "+" .. #p2.rows .. "）")
check(p1.rows[1].id == 70065 and p2.rows[15].id == 70001, "新收的在前（第一筆 " .. tostring(p1.rows[1].id) .. "）")
check(p1.rows[1].uncertain == true and p1.counts.UNCERTAIN == 1, "沒有 settled 的紀錄標 uncertain 並計數")
check(p1.counts.PACKED == 61 and p1.counts.UNPACKED == 2 and p1.counts.RESTORED == 1 and p1.counts.VOID == 1,
    "各狀態計數 PACKED 61 / UNPACKED 2 / RESTORED 1 / VOID 1")
local unc = Index.page({ state = "UNCERTAIN" }, 1)
check(unc.total == 1 and unc.rows[1].id == 70065, "篩「當機前未確認」只剩那一筆")
check(Index.page({ state = "UNPACKED" }, 1).total == 2, "篩已展開 2 筆")
check(Index.page({ q = "70064" }, 1).total == 1, "搜尋完整編號")
check(Index.page({ q = "7006" }, 1).total == 6, "搜尋編號片段（70060..70065）")
check(Index.page({ q = "  ANN " }, 1).total == 2, "搜尋玩家不分大小寫、去空白，展開者也算")
check(Index.page({ q = "p1" }, 1).total == 12, "搜尋收車者 p1（10 筆 PACKED＋2 筆 UNPACKED）")
check(Index.page({}, 99).page == 2 and Index.page({}, -3).page == 1, "頁碼夾在 1..pages")
check(Index.page({ q = "nobody" }, 1).pages == 1 and #Index.page({ q = "nobody" }, 1).rows == 0, "沒有結果仍是 1 頁、0 列")

-- 序列化大小估算（TableNetworkUtils：鍵值各 1 byte 型別、字串 2 byte 長度＋UTF-8、數字 8 byte、每層 4 byte 筆數）
local function wireSize(v)
    if type(v) == "table" then
        local n = 4
        for k, x in pairs(v) do n = n + wireSize(k) + wireSize(x) end
        return n
    elseif type(v) == "string" then return 1 + 2 + #v
    elseif type(v) == "number" then return 1 + 8 end
    return 2
end
quiet = true
local longName = string.rep("W", 120)
for i = 1, 60 do
    Store.write(80000 + i, { state = "PACKED", settled = true, script = "Base." .. longName, name = longName, packedBy = longName,
        history = { { t = base + 1000 + i, ev = "PACKED", by = longName } } })
end
quiet = false
local worst = AdminCommands.handle(newPlayer("admin", true), "adminPage", { q = "", state = "ALL", page = 1 })
check(#worst.rows == 50 and wireSize(worst) < 64 * 1024, "一頁 50 筆、欄位 120 字也只有 " .. wireSize(worst) .. " bytes（遠低於 1 MB）")

print("Index：索引檔壞掉或落後時從桶重建，讀到紀錄就跟上")
Index.flush(nowMs + 10000)
check(files[Index.file()] ~= nil and Index.file() == Store.dir() .. "index.json", "flush 寫出這個世界的 index.json")
Index._resetForTests()
check(Index.page({}, 1).total == 125, "從 index.json 讀回 125 筆")
files[Index.file()] = "{broken"
Index._resetForTests()
quiet = true
local rebuilt = Index.page({}, 1).total
quiet = false
check(rebuilt == 125, "索引壞檔 -> 從桶重建 125 筆")
Index.flush(nowMs + 20000)
-- 索引沒跟上的寫入（寫完紀錄、下次 flush 之前當機）：先拔掉監聽器，模擬索引沒看到
local listeners = Store.listeners
Store.listeners = {}
Store.write(70066, { state = "PACKED", settled = true, packedBy = "late", history = { { t = base + 66, ev = "PACKED", by = "late" } } })
Store.drop({ 70001 })
Store.listeners = listeners
Index._resetForTests()
check(Index.page({ q = "late" }, 1).total == 1 and Index.page({ q = "70001" }, 1).total == 0,
    "桶的代數和索引記的不同：重讀那個桶，補進新紀錄、拿掉不在的")
local s70002 = Store.read(70002)
s70002.state = "VOID"
Store.write(70002, s70002)
check(Index.page({ q = "70002" }, 1).rows[1].state == "VOID", "寫入後索引同步（VOID）")

do -- 桶檔、保留天數、最後看到：主程式的 local 已接近 200 個上限，放進函式
    (function()
        print("Store：桶檔兩份輪流寫，寫到一半的那份被略過，兩份都不完整就不動")
        local id = 999999
        local b = Store.bucketOf(id)
        local function headOf(side)
            local t = files[Store.path(b, side)]
            return t and tonumber(t:match("^MVC1 (%d+)"))
        end
        Store.write(id, { state = "PACKED", settled = true, note = "v1", history = {} })
        local g1 = Store.gen(b)
        local side1 = headOf("a") == g1 and "a" or "b"
        Store.write(id, { state = "PACKED", settled = true, note = "v2", history = {} })
        local side2 = headOf("a") == g1 + 1 and "a" or "b"
        files[Store.path(b, side2)] = files[Store.path(b, side2)]:gsub("\nEND [^\n]*$", "") -- 寫到一半當機：沒有結尾
        Store._resetForTests()
        local back = Store.read(id)
        local genBack = Store.gen(b)
        Store.write(id, { state = "PACKED", settled = true, note = "v3\nEND 1 1", history = {} }) -- 換行要逸出：一筆一行
        local v3 = Store.read(id)
        local saveA, saveB = files[Store.path(b, "a")], files[Store.path(b, "b")]
        files[Store.path(b, "a")], files[Store.path(b, "b")] = "MVC1 9\nbroken", "MVC1 8\nbroken"
        Store._resetForTests()
        quiet = true
        local _, rwhy = Store.read(id)
        local wok, wwhy = Store.write(id, { state = "PACKED", history = {} })
        quiet = false
        local untouched = files[Store.path(b, "a")] == "MVC1 9\nbroken" and files[Store.path(b, "b")] == "MVC1 8\nbroken"
        files[Store.path(b, "a")], files[Store.path(b, "b")] = saveA, saveB
        Store._resetForTests()
        check(side1 ~= side2 and headOf(side1) == g1, "第二次寫進另一份、代數加一（" .. side1 .. " -> " .. side2 .. "）")
        check(back and back.note == "v1" and genBack == g1, "比較新的那份沒寫完：改用上一份（v1）")
        check(v3 and v3.note == "v3\nEND 1 1", "之後的寫入蓋掉沒寫完的那份；欄位裡的換行原樣讀回")
        check(rwhy == "CORRUPT" and wok == nil and wwhy == "CORRUPT" and untouched, "兩份都不完整：讀寫都回 CORRUPT，檔案原樣留給管理員")
        check(Store.bucketOf(-5) == 251 and Store.bucketOf(256 * 7 + 3) == 3, "負的編號也落在 0..255")

        print("Index.prune：結束的紀錄超過保留天數就刪，收起中、未確認、還沒到期的留著")
        local day = 86400000
        local old = nowMs - 40 * day
        local function rec(cid, state, settled, t)
            Store.write(cid, { state = state, settled = settled, history = { { t = t, ev = state, by = "p" } } })
        end
        rec(990001, "UNPACKED", true, old)
        rec(990002, "RESTORED", true, old)
        rec(990003, "PACKED", true, old)
        rec(990004, "UNPACKED", nil, old) -- 當機前未確認
        rec(990006, "RESTORED", nil, old) -- 補回寫到一半當機：同樣未確認
        rec(990005, "VOID", true, nowMs - day)
        Store.mark(990001)
        quiet = true
        local done = Index.prune(nowMs, 30, 256)
        quiet = false
        check(done and select(2, Store.read(990001)) == "NO_SNAPSHOT" and select(2, Store.read(990002)) == "NO_SNAPSHOT",
            "40 天前結束的（已展開、已補回）刪掉")
        check(Store.read(990003) ~= nil and Store.read(990004) ~= nil and Store.read(990006) ~= nil and Store.read(990005) ~= nil,
            "收起中、當機前未確認（展開或補回）、昨天才作廢的留著")
        check(not Store.marked(990001) and Index.page({ q = "990001" }, 1).total == 0, "ModData 標記與索引列一起拿掉")
        rec(990011, "UNPACKED", true, old)
        rec(990012, "UNPACKED", true, old)
        rec(990013, "UNPACKED", true, old)
        quiet = true
        local first = Index.prune(nowMs, 30, 2)
        local second = Index.prune(nowMs, 30, 2)
        quiet = false
        check(first == false and second == true and Index.page({ q = "99001" }, 1).total == 0,
            "一次最多兩個桶，剩下的下一輪再刪")

        print("Index：收起中又 7 天沒人看到的膠囊")
        Store.write(990021, { state = "PACKED", settled = true, history = { { t = nowMs - 10 * day, ev = "PACKED", by = "u" } } })
        Store.write(990022, { state = "PACKED", settled = true, seen = { t = nowMs - day, where = "ground", x = 1, y = 2, z = 0 },
            history = { { t = nowMs - 10 * day, ev = "PACKED", by = "u" } } })
        local unseen = Index.page({ q = "99002", state = "UNSEEN" }, 1)
        check(unseen.total == 1 and unseen.rows[1].id == 990021 and unseen.counts.UNSEEN == 1,
            "10 天前收、之後沒被看到的算；昨天才看到的不算")
        local detail = AdminCommands.handle(newPlayer("admin", true), "adminDetail", { id = 990022 })
        check(detail.seen and detail.seen.where == "ground" and detail.seen.x == 1, "管理面板明細帶最後看到的位置")

        print("Store.seen：同一人同一處一小時內只寫一次；換人、換地方、地上的膠囊換格或過一小時才再寫；不記時間軸、不叫客戶端丟快取")
        Store.write(990031, { state = "PACKED", settled = true, history = { { t = nowMs, ev = "PACKED", by = "s" } } })
        local writes, sentBefore = 0, #sent
        local function count(cid, _, written, q) if cid == 990031 and written and q then writes = writes + 1 end end
        Store.listeners[#Store.listeners + 1] = count
        Store.seen(990031, { where = "player", by = "amy", x = 1, y = 1, z = 0 })
        Store.seen(990031, { where = "player", by = "amy", x = 2, y = 2, z = 0 })
        Store.seen(990031, { where = "player", by = "ben", x = 2, y = 2, z = 0 })
        nowMs = nowMs + Store.SEEN_MS
        Store.seen(990031, { where = "player", by = "ben", x = 3, y = 3, z = 0 })
        local byPlayer = writes
        Store.seen(990031, { where = "ground", x = 5, y = 5, z = 0 })
        Store.seen(990031, { where = "ground", x = 5, y = 5, z = 0 })
        Store.seen(990031, { where = "ground", x = 6, y = 5, z = 0 })
        Store.listeners[#Store.listeners] = nil
        local s = Store.read(990031)
        check(byPlayer == 3, "身上：寫了 3 次（第一次、換人、過一小時），走動不算")
        check(writes == 5 and s.seen.where == "ground" and s.seen.x == 6 and s.seen.by == nil and #s.history == 1,
            "地上：放下算一次、同一格不再寫、被移到隔壁格再寫")
        check(#sent == sentBefore, "看到不算改變：沒有 queryChanged")
        local amy = newPlayer("amy", false)
        local held2 = instanceItem(M.ITEM_LOADED)
        amy.inv:AddItem(held2)
        local at = Query.near(amy, held2.id)
        check(at and at.where == "player" and at.by == "amy" and at.x == 100 and at.y == 200, "Query.near 回傳在誰身上、站在哪")

        print("Store.dir：單機一個存檔一個資料夾（SP_<模式>_<存檔>），名稱裡的特殊字元換成底線")
        local realIsServer, realGetCore, realGetWorld = isServer, getCore, getWorld
        isServer = function() return false end
        getCore = function() return { getGameMode = function() return "Apocalypse" end } end
        getWorld = function() return { getWorld = function() return "10-10-2026_12-00/x" end } end
        Store._resetForTests()
        local spDir = Store.dir()
        isServer, getCore, getWorld = realIsServer, realGetCore, realGetWorld
        Store._resetForTests()
        check(spDir == "MinidoracatVehicleCapsule/SP_Apocalypse_10-10-2026_12-00_x/" and Store.dir() ~= spDir, "單機：" .. spDir)

        print("Store：紀錄再多檔案數也固定（256 桶 × 兩份 + index.json）；刪紀錄是改寫桶，不會多出檔案")
        local many = {}
        for i = 1, 1200 do
            many[i] = 5000000 + i
            Store.write(many[i], { state = "VOID", settled = true, history = {} })
        end
        Index.flush(nowMs + 3600000)
        local prefix = Store.dir()
        local function fileCount()
            local n = 0
            for path in pairs(files) do
                if path:sub(1, #prefix) == prefix then n = n + 1 end
            end
            return n
        end
        local full = fileCount()
        local gone = Store.drop(many)
        check(full == 2 * Store.BUCKETS + 1, "寫了 1200 筆：" .. full .. " 個檔")
        check(#gone == 1200 and fileCount() == full and select(2, Store.read(5000001)) == "NO_SNAPSHOT",
            "刪掉 1200 筆：紀錄不在了，檔案數不變")
    end)()
end

print("Query：一般玩家只能查身上或附近的膠囊，管理員都能查")
local bob = newPlayer("bob", false)
local held = instanceItem(M.ITEM_LOADED)
bob.inv:AddItem(held)
Store.write(held.id, { state = "PACKED", settled = true, script = "Base.PickUpTruck", packedBy = "bob", skin = 2,
    parts = { GasTank = { cond = 90, item = "Base.NormalGasTank", icond = 90, amount = 12.5 }, DoorRearRight = { cond = 0 } },
    manifest = { ["Base.WaterBottle"] = 6 }, history = { { t = base, ev = "PACKED", by = "bob", car = 1 } } })
local groundCap = instanceItem(M.ITEM_LOADED)
Store.write(groundCap.id, { state = "UNPACKED", settled = true, history = { { t = base, ev = "PACKED" }, { t = base + 5, ev = "UNPACKED", by = "ann" } } })
local farCap = instanceItem(M.ITEM_LOADED)
Store.write(farCap.id, { state = "PACKED", settled = true, history = {} })
local function emptyList() return javaList({}) end
loadedSquares["102,201"] = {
    getWorldObjects = function() return javaList({ { getItem = function() return groundCap end } }) end,
    getObjects = emptyList, getVehicleContainer = function() return nil end,
}
local q = Query.query(bob, { held.id, groundCap.id, farCap.id, 99999999 })
local byId = {}
for _, it in ipairs(q.items) do byId[it.id] = it end
local hs = byId[held.id]
check(hs and hs.ok and hs.script == "Base.PickUpTruck" and hs.by == "bob" and hs.skin == 2 and #hs.manifest == 1
    and hs.manifest[1].n == 6, "身上的膠囊：回車種、收車者、塗裝、貨物清單")
local gas
for _, p in ipairs(hs and hs.parts or {}) do if p.id == "GasTank" then gas = p end end
check(gas and gas.a == 12.5 and gas.i == "Base.NormalGasTank" and gas.ic == 90, "零件精簡欄位（油量、物品、物品狀況）")
check(byId[groundCap.id] and byId[groundCap.id].ok and byId[groundCap.id].state == "UNPACKED"
    and byId[groundCap.id].last.by == "ann", "附近地上的膠囊可查（已展開，最後事件 ann）")
check(byId[farCap.id] and byId[farCap.id].ok == false and byId[farCap.id].why == "FAR", "不在身上也不在附近 -> FAR，不回資料")
check(byId[99999999] and byId[99999999].why == "FAR", "不存在的編號對一般玩家也只回 FAR（不洩漏有沒有紀錄）")
local qa = Query.query(newPlayer("admin", true), { farCap.id, 99999999 })
check(qa.items[1].ok and qa.items[2].why == "NO_SNAPSHOT", "管理員可查任何膠囊；沒有紀錄回 NO_SNAPSHOT")
local many = {}
for i = 1, 50 do many[i] = held.id end
check(#Query.query(bob, many).items == Query.MAX_IDS, "一次最多 " .. Query.MAX_IDS .. " 個編號")
local before = #sent
Store.write(held.id, Store.read(held.id))
check(#sent == before + 1 and sent[#sent][2] == "queryChanged" and sent[#sent][3].id == held.id, "寫入快照後廣播 queryChanged")
Store.read(held.id)
check(#sent == before + 1, "只讀不廣播")

print("AdminCommands：一般玩家一律 NOT_ADMIN；明細只回最新 100 筆歷史")
quiet = true
local refused = {}
for _, cmd in ipairs({ "adminPage", "adminDetail", "adminResolve", "adminRestore" }) do
    refused[#refused + 1] = AdminCommands.handle(bob, cmd, { id = held.id }).why
end
check(AdminCommands.handle(bob, "handle", {}) == nil and AdminCommands.handle(bob, "debugPack", {}) == nil,
    "不是 admin* 的指令不處理")
local longH = {}
for i = 1, 130 do longH[i] = { t = base + i, ev = "REJECTED", by = "x" } end
Store.write(70100, { state = "PACKED", settled = true, history = longH })
local det = AdminCommands.handle(newPlayer("admin", true), "adminDetail", { id = 70100 })
quiet = false
check(table.concat(refused, ",") == "NOT_ADMIN,NOT_ADMIN,NOT_ADMIN,NOT_ADMIN", "四個管理指令對一般玩家都拒絕：" .. table.concat(refused, ","))
check(det.ok and #det.history == 100 and det.historyTotal == 130 and det.history[100].t == base + 130, "歷史只送最新 100 筆，另回總數")

print("Loot：開關與權重照沙盒寫進表，重排不疊加，其他物品保留")
local function fakeList()
    return { MechanicShelfTools = { items = { "Base.Wrench", 4 } }, CrateMechanics = { items = { "Base.Jack", 2 } },
        CarSupplyTools = { items = {} }, GasStorageMechanics = { items = { "Base.Funnel", 1 } }, GarageMechanics = { items = {} } }
end
local function weightIn(list, t)
    local items, w = list[t].items, nil
    for i = 1, #items, 2 do if items[i] == Loot.ITEM then w = (w or 0) + items[i + 1] end end
    return w
end
local L = fakeList()
Loot.apply(L, Loot.wanted())
check(weightIn(L, "MechanicShelfTools") == 0.5 and weightIn(L, "CrateMechanics") == 0.5 and weightIn(L, "CarSupplyTools") == 0.5
    and weightIn(L, "GasStorageMechanics") == 0.3 and weightIn(L, "GarageMechanics") == nil, "沒設沙盒＝預設值（住家車庫預設關）")
sandbox = { LootEnabled = true, LootMechanic = true, LootMechanicWeight = 2.5, LootCarSupply = false, LootCarSupplyWeight = 9,
    LootGasStation = true, LootGasStationWeight = 0, LootGarage = true, LootGarageWeight = 1.2 }
Loot.apply(L, Loot.wanted())
Loot.apply(L, Loot.wanted())
check(weightIn(L, "MechanicShelfTools") == 2.5 and weightIn(L, "CrateMechanics") == 2.5, "修車廠兩張表都是 2.5，重排兩次不疊加")
check(weightIn(L, "CarSupplyTools") == nil, "關掉的汽車用品店不出現")
check(weightIn(L, "GasStorageMechanics") == nil, "權重 0 的加油站不出現")
check(weightIn(L, "GarageMechanics") == 1.2, "打開的住家車庫 1.2")
check(L.MechanicShelfTools.items[1] == "Base.Wrench" and L.MechanicShelfTools.items[2] == 4 and L.GasStorageMechanics.items[1] == "Base.Funnel"
    and #L.GasStorageMechanics.items == 2, "原版物品原樣保留")
sandbox.LootEnabled = false
Loot.apply(L, Loot.wanted())
local any = false
for t in pairs(L) do if weightIn(L, t) then any = true end end
check(not any, "總開關關掉：五張表都沒有膠囊")
check(Loot.signature(Loot.wanted()) ~= Loot.signature((function() sandbox.LootEnabled = true; return Loot.wanted() end)()),
    "設定改了簽章就不同（觸發重排）")
sandbox = {}

-- ===== 介面版面：管理面板訊息依欄寬換行、詳情按鈕列放不下就換列（真框架 Text.wrap／fit，實際譯文）=====
print("UI：訊息換行不超出欄寬、行數有上限；按鈕列換列不出欄")
local function uiLayout() -- 獨立函式：主程式的 local 已接近 200 個上限
    local MUI = os.getenv("MUI_LUA_DIR") or "../MinidoracatUIFor42/MOD/MinidoracatUIFor42/Contents/mods/MinidoracatUIFor42/42/media/lua/client/MinidoracatUI/"
    local mui = io.open(MUI .. "V1.lua", "rb")
    if not mui then
        print("  SKIP  找不到框架 " .. MUI .. "（把 MinidoracatUIFor42 clone 在本 repo 同層，或設 MUI_LUA_DIR）")
        return
    end
    mui:close()
    -- 量字：每個字 7px（UTF-8 一個字元算一個字，俄文、法文重音字母不會被當成 2 個）
    local function width(s) return 7 * select(2, s:gsub("[^\128-\191]", "")) end
    UIFont = { Small = "Small", Medium = "Medium" }
    function getTextManager()
        return { MeasureStringX = function(_, _, s) return width(s) end, getFontHeight = function() return 16 end }
    end
    dofile(MUI .. "V1.lua")
    dofile(MUI .. "TextWrap.lua")
    local caps = MinidoracatUI.v1.CAPABILITIES
    caps.window, caps.controls, caps.virtualList, caps.slider = true, true, true, true -- widget 檔要遊戲 UI 類別；這裡只驗文字與排版
    require "MinidoracatVehicleCapsule/UIKit"
    local Kit = M.UIKit
    check(Kit.ok and caps.textWrap == true, "UIKit 接上框架（含 Text.wrap）")
    local function ui(lang)
        local fh = assert(io.open(MEDIA .. "/shared/Translate/" .. lang .. "/UI.json", "rb"))
        local t = Json.decode(fh:read("*a"))
        fh:close()
        return t
    end
    local P = "UI_MinidoracatVehicleCapsule_"
    local DW = 548 -- 980 寬面板的詳情欄
    local msgs = 0
    for _, lang in ipairs({ "EN", "FR", "RU" }) do
        local t = ui(lang)
        for k, s in pairs(t) do
            if k:find("^" .. P .. "Why_") or k == P .. "Restored" or k == P .. "WentTo" or k == P .. "WentToSeen" then
                msgs = msgs + 1
                for _, w in ipairs({ DW, 160 }) do
                    local lines = Kit.lines(s, w, 3)
                    local ok = #lines >= 1 and #lines <= 3
                    for _, line in ipairs(lines) do ok = ok and width(line) <= w end
                    local all = #Kit.wrap(s, w) <= 3
                    ok = ok and (all or lines[3]:sub(-3) == "...")
                    if not ok then check(false, lang .. " " .. k .. " 寬 " .. w .. " 超出或沒標省略") end
                end
                local whole = table.concat(Kit.lines(s, DW, 3), " ")
                if width(s) <= DW * 2 and whole:gsub("%s", "") ~= s:gsub("%s", "") then
                    check(false, lang .. " " .. k .. " 兩行內放得下卻少了字")
                end
            end
        end
    end
    check(msgs >= 30, "三語的拒絕原因與結果訊息都量過（" .. msgs .. " 則）")
    local items = { { width = 120 }, { width = 200 }, { width = 260 }, { width = 180 }, { width = 600 } }
    local rows = Kit.flow(items, DW, 8)
    local inside = true
    for i, it in ipairs(items) do
        if i < #items then inside = inside and it.flowX + it.width <= DW end
    end
    check(inside and rows == 3 and items[3].flowRow == 1 and items[3].flowX == 0 and items[4].flowX == 268
        and items[5].flowRow == 2 and items[5].flowX == 0, "按鈕列放不下就換到下一列、比欄還寬的自成一列（rows=" .. rows .. "）")
    local ru = ui("RU")
    local btns = {}
    for _, key in ipairs({ "GoTo", "GoSeen", "Restore", "VerdictPresent", "VerdictMissing" }) do
        btns[#btns + 1] = { width = width(ru[P .. key]) + 20 }
    end
    Kit.flow(btns, DW, 8)
    inside = true
    for _, b in ipairs(btns) do inside = inside and b.flowX + b.width <= DW end
    check(inside, "RU 五顆詳情按鈕都在詳情欄內")
end
uiLayout()

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
