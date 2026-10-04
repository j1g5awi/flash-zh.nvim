# flash-zh.nvim

基于 [flash.nvim](https://github.com/folke/flash.nvim) 与 [Rime](https://rime.im/) 码表的 neovim 中文跳转插件。

![iShot_2023-10-05_19 32 53](https://github.com/rainzm/flash-zh.nvim/assets/22927169/4c3ca124-0fee-48a2-b7c6-17391afe8d0e)

## 安装

- 依赖于 [flash.nvim](https://github.com/folke/flash.nvim)
- 使用 [lazy.nvim](https://github.com/folke/lazy.nvim) 进行安装，并指定要使用的 Rime 码表：

```lua
return {{
    "rainzm/flash-zh.nvim",
    event = "VeryLazy",
    dependencies = "folke/flash.nvim",
    config = function()
        require("flash-zh").setup({
            dict = {
                -- 一个或多个 .dict.yaml，多个文件会合并
                paths = {
                    vim.fn.expand("~/AppData/Roaming/Rime/yuhao/yuming.full.dict.yaml"),
                },
                -- 可选：只保留该 Lua 模块中出现的字符（即 Rime 的 yuhao_charsets.lua）
                charsets = vim.fn.expand("~/AppData/Roaming/Rime/lua/yuhao/yuhao_charsets.lua"),
                -- 可选：指定字符集子集；默认取四集（ubiquitous/common/tonggui/harmonic）并集
                -- charset_sets = { "common" },
            },
        })
    end,
    keys = {{
        "s",
        mode = { "n", "x", "o" },
        function()
            require("flash-zh").jump({
                chinese_only = false
            })
        end,
        desc = "Flash between Chinese"
    }},
}, {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
        highlight = {
            backdrop = false,
            matches = false
        }
    }
}}
```

## 使用

1. 输入码表的**原生编码**：完整编码跳到该字（例如日月码 `kbhnd` → `的`），只输前缀则匹配所有以该前缀开头的字。
2. 默认工作在中英混杂模式下：小写字母同时按英文匹配；增加选项 `chinese_only` 使其工作在仅中文模式下。
3. `jump` 的参数会传递给 `flash.nvim`，查看 [issue 2](https://github.com/rainzm/flash-zh.nvim/issues/2) 。

**如果想要跳转的地方没有 label 出现，接着输入即可，和查找一样。**

## 配置码表

`setup` 的 `dict` 字段支持几种写法：

- `dict = "路径"`：单个码表。
- `dict = { "路径1", "路径2" }`：多个码表合并。
- `dict = { paths = { ... }, charsets = "...", charset_sets = { ... } }`：
  - `paths`：码表路径列表；
  - `charsets`：可选，指向 Rime 的 `yuhao_charsets.lua`，只保留其中出现的字符；
  - `charset_sets`：可选，指定字符集子集，默认取四集并集。

只保留单字条目（`text` 为单字符且编码为 `[a-z]+`）。首次加载会解析码表并把过滤结果按 mtime 缓存到
`stdpath("cache")/flash-zh`，之后启动很快。未配置 `dict` 时不会匹配中文。

## 感谢

- [hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)
