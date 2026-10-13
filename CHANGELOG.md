# 變更紀錄

本專案所有重要變更都會記錄在此檔案。

格式遵循 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
並遵循 [Semantic Versioning](https://semver.org/spec/v2.0.0.html)。

## [Unreleased]

### 新增
- 在 oil buffer 中呼叫 `:OilmarksAdd` 可把目前目錄收成書籤
- 跳轉目錄書籤時優先用 oil.open，否則 fallback 到 `:edit`

## [0.0.0] - 2026-10-01

### 新增
- 初始實作 oil 風格的全域扁平書籤清單
- 可編輯 buffer，只在 `:w` 時提交（原子寫入 `stdpath("data")/oilmarks/bookmarks.lua`）
- 指令：`:Oilmarks`（支援 `float` / `trash`）、`:OilmarksAdd`、`:OilmarksNext`、`:OilmarksPrev`、`:OilmarksReload`
- Tab 分隔欄位，隱藏 id，名稱、位置（`path:line` 或 `path:line:col`）、註解
- 垃圾桶：刪行 + `:w` 移入垃圾桶；`r` + `:w` 還原；在垃圾桶刪行 + `:w` 永久刪除
- 跳轉時依儲存的 `line_text` 重對齊行號（找最接近的相同文字，找不到則標為 stale）
- 在原始檔放置標記
- 可設定快捷鍵、浮動視窗、標記文字
