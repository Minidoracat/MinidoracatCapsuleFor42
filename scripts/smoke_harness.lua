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
local M = MinidoracatVehicleCapsule
local Json, Store = M.Json, M.Store

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
local snap = { v = 1, state = "PACKED", script = "Base.PickUpTruck", modData = nasty, history = {} }
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
check(select(2, Store.setState(42, Store.read(42), "RESTORED", player)) == "BAD_TRANSITION", "UNPACKED 不能再轉 RESTORED")

Store.write(50, { state = "PACKED", history = {} })
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
Store.write(61, { state = "PACKED", history = {} })
corruptWrites = true
quiet = true
local c61, cwhy = Store.claim(61, player)
quiet = false
corruptWrites = false
check(c61 == nil and cwhy == "WRITE_FAILED", "claim 寫壞 -> WRITE_FAILED，不回快照")
local ok2, why2, path2 = Store.write(62, { modData = { bad = function() end } })
check(ok2 == nil and why2 == "MODDATA_UNSUPPORTED" and path2 == "modData.bad", "存不成 JSON -> MODDATA_UNSUPPORTED＋路徑")
check(files["MinidoracatVehicleCapsule/packs/62.json"] == nil, "被拒時不留快照檔")

print()
if failures > 0 then
    print(failures .. " 項失敗")
    os.exit(1)
end
print("全部通過")
