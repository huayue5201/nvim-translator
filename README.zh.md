# translator.nvim

一个 Neovim 原生翻译插件。后端使用 **Rust** 编写(无需 Python);Neovim 通过
`jobstart` 与后端通信,协议为 `argv → stdout JSON`。

[English README](README.md)

## 环境要求

- Neovim 0.8+(推荐 0.10+;TTS 和 Anki 功能需要 0.10+)
- Rust 工具链(`cargo`)—— 仅首次构建后端二进制时需要
- `curl` —— Anki 功能需要(macOS/Linux 自带)

## 安装

使用你喜欢的插件管理器安装,然后构建后端:

```sh
# lazy.nvim
{
  "huayue5201/nvim-translator",
  build = "make build",
}
```

或手动构建:

```sh
cd path/to/nvim-translator
make build
```

`make build` 会执行 `cargo build --release` 并把二进制复制到 `bin/translator`。

## 用法

| 命令 | 作用 |
| ----------------- | ------------------------------------------------------- |
| `:Translate` | 回显翻译(词 / 选区 / 文本) |
| `:TranslateW` | 在浮动窗口中显示翻译 |
| `:TranslateR` | 用译文替换可视选区 |
| `:TranslateX` | 翻译 `*`(系统剪贴板)寄存器 |
| `:TranslateI` | 交互式输入文本后翻译 |
| `:TranslateApi` | 翻译代码 API 符号及其文档 |
| `:TranslateSay` | 朗读原文(`!` = 朗读译文) |
| `:TranslateA` | 把上次翻译加入 Anki(通过 AnkiConnect) |
| `:TranslateH` | 打开翻译历史 |
| `:TranslateL` | 打开调试日志 |

文本来源优先级:

1. 命令后的显式文本:`:Translate hello world`
2. 可视选区(char / line / block 均可)
3. 行范围:`:3,5Translate`
4. 光标下的单词

翻译浮动窗口打开时,底部会显示这些二级操作键(窗口**不会**抢占焦点;这些键
只在窗口打开期间映射,关闭后恢复):

| 键 | 作用 |
| ------ | -------------------------- |
| `s` | 朗读原文 |
| `S` | 朗读译文 |
| `a` | 加入 Anki(编辑弹窗) |
| `y` | 复制译文 |
| `<Esc>` | 关闭窗口 |

移动光标同样会关闭窗口,与之前一致。

选项(以 `--key=value` 形式传入):

```vim
:Translate --engines=google,youdao hello world
:Translate --target_lang=en --source_lang=zh 你好
```

末尾的 `!` 会交换源/目标语言。它仅在显式指定语言时生效;自动方向下插件已经
会为你选择正确方向。

### 自动方向(双语自动互翻)

默认情况下插件会检测文本并自动选择方向,因此两种方向都无需参数即可工作:

```vim
:Translate hello     " en -> zh
:Translate 你好      " zh -> en
```

- 包含 CJK(中文 / 假名 / 谚文)→ `zh → en`
- 否则 → `auto → zh`

显式 `--source_lang` / `--target_lang` 会覆盖自动检测:

```vim
:Translate --source_lang=zh --target_lang=ja 你好
```

### 交互式输入

`:TranslateI` 会打开一个预填当前上下文(光标下单词 / 可视选区 / 行范围)的
输入框,你可以在翻译前修改文本。它支持与 `:Translate` 相同的 `--flags` 和
`!`:

```vim
:TranslateI                  " 输入框,预填 <cword>
:TranslateI --engines=llm    " 输入框,随后用 llm 引擎翻译
:TranslateI!                 " 输入框,交换语言后翻译
```

结果显示在一个固定、居中的浮动窗口中;光标会移入窗口,方便选择和复制译文。
`q` / `<Esc>` / 离开窗口即可关闭。

## 引擎

`google`、`youdao`、`baidu`、`bing`、`baicizhan`、`haici`、`iciba`、
`trans`(translate-shell CLI)、`sdcv`(StarDict CLI)、`llm`
(OpenAI 兼容 LLM API),以及 `api`(API 文档引擎,见下文)。

`trans` 和 `sdcv` 会调用外部命令,需要单独安装。部分免费接口(`google`、
`bing`、`youdao`)在某些地区可能需要代理。

### LLM 引擎

一个通用引擎即可覆盖所有 OpenAI 兼容提供商(DeepSeek、OpenAI、Qwen、Kimi、
Doubao、本地 Ollama 等)。配置一次后,把 `llm` 设为默认引擎即可:

```lua
vim.g.translator_llm = {
    provider = "deepseek",   -- 预设: deepseek|openai|ollama|qwen|kimi|doubao
    api_key = "sk-...",       -- ollama 不需要
    -- model = "deepseek-chat", -- 可选,预设会提供默认值
    -- prompt = "...",         -- 可选,{sl} 和 {tl} 会被替换
    -- timeout = 60,           -- 可选,单位秒
}
vim.g.translator_default_engines = { "llm" }
```

除了 `provider` 也可以直接传 `base_url`(例如自建端点)。API key 通过环境变量
传给后端,绝不经过 argv,因此不会泄漏到日志或进程列表。

`api_key` 支持多种写法,无需硬编码:

```lua
vim.g.translator_llm = {
    provider = "deepseek",
    -- 1) 字符串
    -- api_key = "sk-...",
    -- 2) 惰性函数
    api_key = function() return os.getenv("DEEPSEEK_API_KEY") end,
    -- 3) 环境变量名
    -- api_key_name = "DEEPSEEK_API_KEY",
    -- 4) 嵌套 env 形式(codecompanion 风格)
    -- env = { api_key = function() return os.getenv("DEEPSEEK_API_KEY") end },
    model = "deepseek-chat",
    -- 也接受 codecompanion 风格的 model 默认值:
    -- schema = { model = { default = "deepseek-chat" } },
}
```

`provider` 也可写成 `name`(`name = "deepseek"`)。

## API 文档翻译

在代码编辑器里,大部分翻译都发生在代码上,因此 `api` 引擎(以及
`:TranslateApi` 命令)会**连同文档一起**翻译代码符号,而不是做普通的词典查询。

```vim
:TranslateApi                          " 光标下的单词
:TranslateApi requests.get             " 显式符号
:TranslateApi --target_lang=en map     " 显式目标语言
```

工作流程:

1. 用当前缓冲区的 `filetype` 作为编程语言提示(如 `python`、`rust`、
   `javascript`)。
2. 把符号发给已配置的 LLM,并使用 API 文档专用提示词。
3. 由模型判断输入是否为 API;如果不是(例如普通单词),则回退为普通翻译。

输出条目(只显示适用的部分):

| 条目 | 内容 |
| -------- | --------------------------------------------------- |
| 概述 | 一句话说明该 API 的作用(译文) |
| 签名 | 精确的签名 / 调用形式(保持原文) |
| 参数 | 参数说明(译文) |
| 返回值 | 返回值说明(译文) |
| 示例 | 简短用法示例(代码保持原文) |
| 备注 | 弃用 / 版本 / 注意事项(译文) |

代码、签名、标识符和参数名始终保持原文,只翻译人类语言说明。

`api` 引擎与 `llm` 引擎共用 LLM 配置,因此需要 `vim.g.translator_llm`
(见上文)。

建议按键映射:

```lua
vim.keymap.set("n", "<localLeader>tld", "<Cmd>TranslateApi<CR>", { desc = "API 文档翻译" })
vim.keymap.set("v", "<localLeader>tld", ":TranslateApi<CR>", { desc = "API 文档翻译" })
```

## 文本转语音(朗诵)

朗读原文或译文。

| 命令 | 作用 |
| ------------------ | ------------------------------------ |
| `:TranslateSay` | 朗读原文(单词/句子) |
| `:TranslateSay!` | 朗读译文(目标语言) |

`TranslateSay` 朗读**上次翻译的文本**(如果还没翻译过,则朗读光标下单词 /
可视选区)。`TranslateSay!` 朗读目标语言的译文。

### TTS 引擎

```lua
vim.g.translator_tts_engine = "say"   -- "say"(本地,默认) | "google"(在线)
```

- **`say`(默认)** —— 使用操作系统内置 TTS,无需网络和额外依赖:
  - macOS:`say`(内置,支持 en_US + zh_CN 语音)
  - Linux:`espeak-ng` / `espeak` / `spd-say`(安装其一,如
    `sudo apt install espeak-ng`)
  - Windows:PowerShell `System.Speech`
- **`google`** —— 在线 Google TTS,语音更自然,需要网络和音频播放器:
  - macOS:`afplay`(内置)
  - Linux:`mpv` / `ffplay` / `aplay`
  - Windows:PowerShell `SoundPlayer`

示例按键映射:

```lua
vim.keymap.set("n", "<localLeader>tls", "<Cmd>TranslateSay<CR>", { desc = "读原文" })
vim.keymap.set("n", "<localLeader>tlt", "<Cmd>TranslateSay!<CR>", { desc = "读译文" })
```

## Anki 卡片(背单词)

通过 [AnkiConnect](https://git.sr.ht/~foosoft/anki-connect) 把上次翻译加入
Anki。

### 依赖

1. 安装 [Anki](https://apps.ankiweb.net/)。
2. 在 Anki 中:**工具 → 插件 → 获取插件…**,输入代码 `2055492159`
   (AnkiConnect),重启 Anki。
3. 使用该功能时保持 Anki 运行(AnkiConnect 监听 `127.0.0.1:8765`)。

### 用法

先翻译一个单词/句子,再运行 `:TranslateA`(或映射到按键):

```vim
:Translate naive
:TranslateA
```

`:TranslateA` 会打开一个预填译文的编辑弹窗,保存前可以调整每个字段:

| 键 | 作用 |
| ---------------- | ---------------------- |
| `<Tab>`/`<S-Tab>` | 切换字段 |
| `<Up>`/`<Down>` | 浏览字段历史 |
| `<CR>` | 保存到 Anki |
| `q` / `<Esc>` | 取消 |

首次使用时插件会自动创建牌组和笔记类型(幂等),无需手动配置 Anki。重复笔记
(相同正面文本)会被跳过。

```lua
vim.keymap.set("n", "<localLeader>tla", "<Cmd>TranslateA<CR>", { desc = "加入 Anki" })
```

### 卡片字段

| 字段 | 内容 |
| -------- | ---------------------------------------- |
| Front | 源文本(单词 / 短语 / 句子) |
| Back | 译文 + 词典释义 |
| Phonetic | 发音 |
| Example | 预留(暂时为空) |

### Anki 配置

```lua
vim.g.translator_anki_port = 8765      -- AnkiConnect 端口
vim.g.translator_anki_deck = "翻译"    -- 牌组名(自动创建)
vim.g.translator_anki_model = "translator" -- 笔记类型(自动创建)
```

## 配置

```lua
vim.g.translator_target_lang = "zh"      -- 默认目标语言
vim.g.translator_source_lang = "auto"    -- 默认源语言
vim.g.translator_proxy_url = ""          -- 例如 "socks5://127.0.0.1:1080"
vim.g.translator_history_enable = true   -- 持久化历史
vim.g.translator_window_type = "float"   -- "float" | "preview"
vim.g.translator_window_max_width = 0.4  -- 列数占比
vim.g.translator_window_max_height = 0.3 -- 行数占比
vim.g.translator_default_engines = { "google", "youdao" }
vim.g.translator_debug = false           -- 写入日志到数据目录

vim.g.translator_tts_engine = "say"      -- "say" | "google"
vim.g.translator_anki_deck = "翻译"      -- Anki 牌组名
```

## 文档

`:help translator` —— 完整的 Vim 帮助文档(`doc/translator.txt`)。

## 开发

```sh
make build   # cargo build --release && 安装到 bin/
make test    # cargo test(响应解析器的离线单元测试)
make clean
```

后端是 `rust/` 下的单一 crate。每个引擎位于 `rust/src/engines/`,在 stdout
返回一个 JSON 对象:

```json
{
  "text": "hello",
  "status": 1,
  "results": [
    {
      "engine": "google",
      "sl": "en",
      "tl": "zh",
      "text": "hello",
      "phonetic": "",
      "paraphrase": "你好",
      "explains": ["[感叹词] 你好;喂"],
      "alternative": []
    }
  ]
}
```

## 健康检查

```vim
:checkhealth translator
```
