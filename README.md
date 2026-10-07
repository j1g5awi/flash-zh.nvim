# flash-zh.nvim

基于 [flash.nvim](https://github.com/folke/flash.nvim) 与 [Rime](https://rime.im/) 码表的 neovim 中文跳转插件。

*仅支持全码定长码（任何双拼）与全码不定长无空前缀码（日月、灵明、清韵），不支持如倉頡的不定长码。*

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
                -- filter_charset 可选，默认 true：只保留内置常用字集（11,177 字）
                -- filter_charset = true,
            },
        })
        -- 在 config 里绑定，晚于 flash.nvim 的映射，确保覆盖生效
        vim.keymap.set({ "n", "x", "o" }, "s", function()
            require("flash-zh").jump()
        end, { desc = "Flash between Chinese" })
    end,
}}
```

## 使用

1. 输入码表的**原生编码**：完整编码跳到该字（例如日月码 `kbhnd` → `的`），只输前缀则匹配所有以该前缀开头的字。
2. 中英混杂：小写字母同时按英文匹配（小写字母也匹配其大写形式）。
3. `jump` 的参数会传递给 `flash.nvim`，查看 [issue 2](https://github.com/rainzm/flash-zh.nvim/issues/2) 。

**如果想要跳转的地方没有 label 出现，接着输入即可，和查找一样。**

## 配置码表

`setup` 的 `dict` 字段支持几种写法：

- `dict = "路径"`：单个码表。
- `dict = { "路径1", "路径2" }`：多个码表合并。
- `dict = { paths = { ... }, filter_charset = true }`：
  - `paths`：码表路径列表；
  - `filter_charset`：可选，默认 `true`，只保留内置的常用字并集（11,177 字）；设为 `false` 则保留码表中所有单字。

加载时还会自动做一次**前缀码去重**（**没有开关，始终开启**）：删除**某个字里"是该字另一个码的前缀"**的码
（某字同时有 `e` 和 `ejk` 时删掉 `e`，因为输 `e` 本来也能通过 `ejk` 命中它）。
只在同一个字内部去重，**绝不跨字删码**，所以任何字都不会因此消失：
实测五张码表的字条目数完全一致，被删的码 100% 是"同一字更长码的前缀"
（虎码 14351→9287 条、星空键道 17691→8915 条）。

只保留单字条目（`text` 为单字符且编码为 `[a-z]+`）；首次加载会解析码表并把过滤结果按 mtime 缓存到
`stdpath("cache")/flash-zh`，之后启动很快。未配置 `dict` 时不会匹配中文。

### 前缀码去重的效果

同一组完整编码输入、`filter_charset = true`、每行是 n 次击键的合计（跑三次取中位数，单次抖动约 ±30%）。
"未过滤"一列只是对照，用来显示这一步去掉了什么代价：

| 码表 | 状态 | 条目/码 | n | 扫描总和 | 每击均值 | 最坏 | 最大 pattern | matches |
|---|---|---|---:|---:|---:|---:|---:|---:|
| 日月 quick+full | 未过滤 | 11177/14008 | 36 | 318ms | 8.8ms | 96ms | 15 KB | 1715 |
| 日月 quick+full | 过滤后 | 11177/13574 | 36 | **35ms** | **1.0ms** | 2ms | <1 KB | 1714 |
| 星空键道 | 未过滤 | 8450/17691 | 45 | 406ms | 9.0ms | 51ms | 2 KB | 3091 |
| 星空键道 | 过滤后 | 8450/8915 | 45 | **175ms** | **3.9ms** | 43ms | 2 KB | 3081 |
| 仓颉五代 | 未过滤 | 11067/11499 | 21 | 702ms | 33.4ms | 99ms | 8 KB | 1747 |
| 仓颉五代 | 过滤后 | 11067/11498 | 21 | 724ms | 34.5ms | 125ms | 8 KB | 1747 |
| 朙月拼音 | 未过滤 | 11021/416 | 26 | 248ms | 9.6ms | 58ms | 4 KB | 1866 |
| 朙月拼音 | 过滤后 | 11021/414 | 26 | 247ms | 9.5ms | 56ms | 4 KB | 1866 |
| 虎码 | 未过滤 | 11177/14351 | 39 | 712ms | 18.3ms | 60ms | 5 KB | 2566 |
| 虎码 | 过滤后 | 11177/9287 | 39 | **151ms** | **3.9ms** | 23ms | 1 KB | 2567 |

去重后扫描快 1–9×（日月 318→35ms、虎码 712→151ms、星空键道 406→175ms）；
仓颉五代、朙月拼音本身几乎没有"同字冗余码"，所以持平。**字条目数不变、matches 基本不变**
（1715→1714、3091→3081、1747→1747、1866→1866、2566→2567），即**零丢字**。
冗余短码被删后，由它派生的假分段也一起消失，例如日月 `ksshc` 的正则从 6478B/7 分支缩到 **31B/1 分支**，命中数不变。

## 感谢

- [hop-zh-by-flypy](https://github.com/zzhirong/hop-zh-by-flypy)
