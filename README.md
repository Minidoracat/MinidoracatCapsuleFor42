# Minidoracat Vehicle Capsule for B42

把停著的車收進膠囊，丟出去就展開，改裝、車況與貨物一起保存；收起來的車不在世界上，KI5 這類吃效能的車也能收起來減輕負擔。單人與多人皆可用。

Project Zomboid Build 42 MOD。**開發中，尚未發布**（首發版 0.1.0 準備中）。

## 需要

- [Minidoracat UI Library for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701)（必裝：3D 預覽與管理面板）
- [Minidoracat Vehicle Manager](https://steamcommunity.com/sharedfiles/filedetails/?id=3813972279)（選用：綁定的車只有車主和被分享「拖曳」權限的人能收，展開後車主不變）
- [Minidoracat Economy](https://steamcommunity.com/sharedfiles/filedetails/?id=3801482125)（選用：管理員把空膠囊上架到經濟中心販售，不需要整合程式）

## 功能

- **收車**：右鍵車輛「收進膠囊」，約 10 秒；條件是引擎熄火、車上沒人、背包有空膠囊。選單逐項列出條件，沒符合的寫出要怎麼做。權限：在 Vehicle Manager 綁定的車只有車主和被分享「拖曳」權限的人能收（管理員要開越權）；其他車照沙盒（預設要有車鑰匙，可改任何人或只有管理員），管理員一律可收。沒權限時選單寫原因，點了會跳通知。
- **原樣保存**：車種、塗裝、零件與車況（含改裝與拆掉的零件）、油量、胎壓、電瓶、門窗與門鎖、鑰匙編號，以及車上所有貨物（用原物件保存，水量、新鮮度、血跡都在）。原版車與 KI5 車都實測過。
- **丟出展開**：物品欄右鍵「丟出膠囊」，游標框出車身（綠框放得下、紅框寫原因），丟出「咻～」、落地「蹦」一聲冒煙閃光，車原樣出現，貨物放回原容器；可設定歸還一顆空膠囊。
- **按下按鈕**：貨物太重、膠囊撿不起來時，對地上的膠囊「按下按鈕」，車出現在旁邊。
- **貨物鎖**：裝了車的膠囊不能直接拿出貨物（拖曳、全部拿取、吃喝、裝填、製作都拿不到），要展開車才拿得到；伺服器也會把被硬拿出的貨物放回。沙盒選項「可以從膠囊拿出貨物」開啟時改成只能拿出、不能放進去，拿走的從紀錄刪掉；剛收好與當機前未確認的膠囊照樣鎖住。
- **提示框與 3D 預覽**：滑鼠移到膠囊上看車名、車況、油量、電瓶、缺件、改裝與貨物；右鍵「預覽車輛」旋轉查看車種外觀。
- **當機不複製**：收車與展開後約 5 秒才標成已存好；當機前未確認的紀錄由管理員到現場判定，確定落盤的舊膠囊裡多出來的貨物會自動清掉。
- **紀錄與補回**：每顆膠囊只能展開一次，每次收車、展開、拒絕、補回都有紀錄；管理面板（家族工具列「車輛膠囊管理」）可搜尋、看時間軸與貨物清單、前往紀錄位置、補回車輛（只補車，貨物列清單由管理員決定）。
- **取得方式**：戰利品（修車廠、汽車用品店、加油站修車區、住家車庫，四個地點各自開關與權重，管理面板也能改）、管理員發放、經濟中心上架。
- **特效不影響殭屍**：煙霧與閃光只畫在畫面上；聲音預設不引殭屍，可用沙盒調範圍。

完整玩家說明見 Steam 說明串稿 [`STEAM_DISCUSSION_guide.md`](STEAM_DISCUSSION_guide.md)（英文 [`STEAM_DISCUSSION_guide_EN.md`](STEAM_DISCUSSION_guide_EN.md)）。

設計稿：[`docs/design/vehicle-capsule-plan.html`](docs/design/vehicle-capsule-plan.html)（`.packed.html` 是內嵌素材的單檔版）

## 給服主

- 伺服器紀錄存在 `Zomboid/Lua/MinidoracatVehicleCapsule/`（不在世界存檔裡）；收起中的車只能靠它補回，請列入備份。
- 用 Minidoracat Cleaner 時，把 `MinidoracatVehicleCapsule.LoadedCapsule` 加進「物品保護清單」（ProtectList），地上裝了車的膠囊就不會被清掉。
- 物品 ID：空膠囊 `MinidoracatVehicleCapsule.Capsule`（上架、發放用）、裝了車的膠囊 `MinidoracatVehicleCapsule.LoadedCapsule`（不能上市場）。

## 安裝

- Steam Workshop：（首發後補上連結）
- 手動安裝：把 `MOD/MinidoracatVehicleCapsuleFor42/Contents/mods/MinidoracatVehicleCapsuleFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatVehicleCapsuleFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- 提交／發版前閘門（repo 根目錄，任一 FAIL 不得定版）：`uv run scripts/verify_mod.py`（靜態檢查，見 [`scripts/verify_mod.py`](scripts/verify_mod.py)）與 `lua scripts/smoke_harness.lua`（行為測試：紀錄存取、狀態轉換、當機判定、補回、貨物鎖，見 [`scripts/smoke_harness.lua`](scripts/smoke_harness.lua)）
- 實機 E2E：照 `../pz-family-docs/e2e.md` 的流程跑專用伺服器＋客戶端；本 repo 的情境放在本機技能 `.claude/skills/vehiclecapsule-e2e/`（不入庫）。改到網路指令、伺服器寫檔、沙盒、權限或介面時補情境並跑一次。
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
