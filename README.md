# oilmarks

Neovim 書籤插件。畫面上是一份可編輯的 buffer，用法對齊 [oil.nvim](https://github.com/stevearc/oil.nvim)：平常的編輯動作只改 buffer，`:w` 才寫回資料檔

一筆書籤是「某個檔案的某一行」或「某個目錄」加上名稱與註解 清單是全域、扁平的 沒有資料夾，也沒有進入下一層

需要 Neovim 0.10 以上（欄位對齊用 inline virtual text）

## 安裝

lazy.nvim：

```lua
{
  dir = "~/code/oilmarks",
  config = function()
    require("oilmarks").setup()
    vim.keymap.set("n", "<leader>mm", function() require("oilmarks").open() end, { desc = "Oilmarks" })
    vim.keymap.set("n", "<leader>ma", function() require("oilmarks").add() end, { desc = "Add bookmark" })
  end,
}
```

插件本身不綁全域按鍵

## 使用

- `:Oilmarks` 在目前視窗打開清單 `:Oilmarks float` 用浮動視窗 `:Oilmarks trash` 打開垃圾桶
- `:OilmarksAdd` 把目前檔案的目前行收進來，或在 oil buffer 裡把目前目錄收進來，問一句註解 這個動作會立刻落盤，因為它不是在 oilmarks buffer 裡編輯
- `:OilmarksNext` / `:OilmarksPrev` 在目前檔案裡跳下一筆／上一筆
- `:OilmarksReload` 從磁碟重讀 磁碟比記憶體新時，`:w` 會拒絕覆蓋並提示這個指令

Buffer 裡：

| 鍵 | 作用 |
| --- | --- |
| `<CR>` | 跳到該行。浮動視窗會回到先前的視窗 |
| `<C-v>` / `<C-s>` | 垂直／水平分割後跳 |
| `p` | 下方預覽，不離開清單 |
| `-` / `q` | 關閉。一般視窗會回到先前的 buffer |
| `g?` | 短說明 |
| `<Tab>` / `<S-Tab>` | insert 模式在欄位間移動 |
| `:w` | 提交。會先顯示建立、複製、更新、刪除的數量 |

刪行之後要 `:w` 才進垃圾桶。複製一行再貼上，隱藏的 id 會被當成複本，存檔時給新 id。解析失敗整次存檔中止，不會寫一半

垃圾桶裡 `r` 把該列標成要還原，`:w` 才移回清單。在垃圾桶刪行再 `:w` 是永久刪除

## 畫面上的一行

實際文字是 Tab 分隔，id 被 Conceal：

```text
a1b2c3d4    auth middleware    ~/proj/src/auth.lua:42    refresh token 過期
```

看到的是名稱、位置、註解 位置寫成 `path:line` 或 `path:line:col`，`~` 會展開

目錄書籤的位置是目錄路徑（行號固定 1） 改了位置之後，存檔時會重抓那一行的內容，當作之後對齊用的錨點

## 行號漂移

跳轉時才重對齊，不在背景掃檔：

1. 該行內容仍等於存下來的 `line_text`：直接跳
2. 對不上：在檔案裡找相同文字，取離舊行號最近的一筆，跳過去。新行號只留在記憶體，oilmarks buffer 會變成未存檔，`:w` 才落盤
3. 找不到：標成 stale，仍跳到舊行號，不自動刪。檔案不見就只警告，不建立空檔

## 資料檔

預設是 `stdpath("data")/oilmarks/bookmarks.lua`。原子寫入。載入失敗時拒絕覆蓋

資料層是 `lists[]`，每一份清單有自己的 `entries` 和 `trash` v1 只用第一份 `root`，畫面也只編這一份 之後要加第二份清單不用改檔案形狀

```lua
return {
  version = 1,
  lists = {
    {
      id = "root",
      name = "bookmarks",
      entries = {},
      trash = {},
    },
  },
}
```

## 模組

- `store` 唯一碰磁碟
- `parse` / `diff` 只管文字跟快照的差異
- `anchor` 只管行號重對齊
- `view` 只管 buffer、conceal、欄位
- `actions` 把上面串起來
- `signs` 在原始檔放標記，不提供另一套操作

## 設定

```lua
require("oilmarks").setup({
  save_path = nil,
  skip_confirm = false,
  prompt_on_select_if_modified = true,
  sign_text = "⚑",
  stale_sign_text = "!",
  float = { border = "rounded", width = 0.82, height = 0.62 },
  keymaps = {
    ["<CR>"] = "select",
    ["<C-v>"] = "select_vsplit",
    ["<C-s>"] = "select_split",
    ["p"] = "preview",
    ["-"] = "close",
    ["q"] = "close",
    ["g?"] = "help",
    ["r"] = "restore",
  },
})
```
