# Minidoracat Vehicle Capsule for B42

把停著的車收進膠囊，丟出去就展開，改裝、車況與貨物一起保存。

Project Zomboid Build 42 MOD。**開發中，尚未發布。** 需要 [Minidoracat UI Library for B42](https://steamcommunity.com/sharedfiles/filedetails/?id=3789836701)。

## 功能

- 收車：車主把停著的車收進空膠囊，改裝、塗裝、車況、油量與貨物一起保存
- 丟出展開：游標選落點（綠框放得下、紅框寫原因），落地冒煙後車原樣出現；太重撿不起來時可在地上按下按鈕展開
- 提示框與 3D 預覽：滑鼠移到膠囊上看車況與貨物，右鍵預覽車種外觀
- 取得方式：戰利品（四類地點各自開關與權重）、管理員發放、經濟中心上架
- 紀錄與補回：每顆膠囊只能展開一次；管理員查得到去向、遺失時補回車輛

設計稿：[`docs/design/vehicle-capsule-plan.html`](docs/design/vehicle-capsule-plan.html)

## 安裝

- Steam Workshop：（首次上傳後補上連結）
- 手動安裝：把 `MOD/MinidoracatVehicleCapsuleFor42/Contents/mods/MinidoracatVehicleCapsuleFor42` 複製到 `%USERPROFILE%\Zomboid\mods\` 並將資料夾改名為 `MinidoracatVehicleCapsuleFor42`

## 開發

- `link_workshop.bat`：手動同步、唯讀狀態與歸檔卸載；MOD 以實體副本放入 `Zomboid\Workshop\` 與 `Zomboid\mods\`，不使用目錄連結
- `PZ_Test.bat`：暗色點選視窗，啟動前增量同步目前 MOD 與家族依賴；首次預設 no-Steam，之後記住各專案的選擇。需要換檔但遊戲仍在執行時拒絕同步與新啟動，不停止既有遊戲；完整驗證與資料邊界見 `../pz-family-docs/tools.md`
- `Publish_Workshop.bat`：發布到 Steam Workshop（需 Steam 用戶端已登入；可選擇只更新內容／封面／簡介；首發仍走遊戲內上傳器）

## 版本

版本號格式：`{PZ 版本}-{mod 版本}`（例 `42.21.0-0.1.0`），詳見 [CHANGELOG.md](CHANGELOG.md)。

## 作者

Minidoracat — [Discord](https://discord.gg/Gur2V67) | [Twitch](https://www.twitch.tv/minidoracat)
