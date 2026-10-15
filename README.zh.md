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
| `:TranslateCancel` | 中断正在进行的翻译请求 |
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

翻译请求进行中时,`<Esc>` 会中断它(结束后端进程并停止旋转提示)。该键仅在
普通/可视模式下、且你尚未自行映射该键时临时绑定,请求结束后自动移除。可用
`cancel_key = false` 关闭,或用 `:TranslateCancel` 显式中断。

多引擎结果**增量显示**:**第一个**引擎返回就弹出浮窗,之后每多一个引擎就在底部追加
一段、窗口随之增高(按到达顺序),不再等最慢的源。仍有请求未返回时,末尾显示
`⏳ 还有 N 个翻译中…`,全部返回后自动消失;窗口只长大、不跳动。设 `incremental = false`
可回退为“全部返回后一次性显示”。仅对 `:Translate` / `:TranslateI` 浮窗生效。

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

### 双语对照

窗口模式(`:TranslateW` / `:TranslateI`)可以把原文和译文**逐句交错**显示,
而不是把整段译文堆在原文下方:

```vim
:TranslateW --bilingual hello. how are you?
```

每个引擎的 `paraphrase` 会与原文逐句交错:一句原文后面紧跟一句译文
(译文以 `↳` 标记):

```
⟦ hello. how are you? ⟧

─── google ───
  hello.
  ↳ 你好。
  how are you?
  ↳ 你好吗？
```

词典式释义(`explains`)和音标保持不变。

全局开启:

```lua
vim.g.translator_bilingual = true
```

也可用 `--bilingual` / `--no-bilingual` 在单次调用中覆盖。

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

### 百度引擎

配置 [百度翻译开放平台](https://fanyi-api.baidu.com/) 的 `appid` + `key` 后,
`baidu` 引擎即可翻译**整句**。不配置凭证时会回退到免费的 `/sug` 词典接口,
该接口**仅支持单词**(整句返回空)。

```lua
require("translator").setup({
    engines = { "baidu", "google" },
    baidu = {
        appid = "2024xxxxxxxxx",
        key   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        -- 也可读环境变量名:
        -- appid_name = "BAIDU_APPID", key_name = "BAIDU_KEY",
    },
})
```

官方接口按源文字符数计费;个人使用免费(免费实名认证后 100万字符/月)。

### LLM 引擎

一个通用引擎即可覆盖所有 OpenAI 兼容提供商(DeepSeek、OpenAI、Qwen、Kimi、
Doubao、本地 Ollama / llama.cpp 等)。配置一次后,把 `llm` 设为默认引擎即可:

```lua
require("translator").setup({
    engines = { "llm" },
    llm = {
        provider = "deepseek",   -- 预设: deepseek|openai|ollama|qwen|kimi|doubao
        api_key = "sk-...",       -- 本地端点(ollama / llama.cpp)不需要
        -- model = "deepseek-chat", -- 可选,预设会提供默认值
        -- prompt = "...",         -- 可选,{sl} 和 {tl} 会被替换
        -- timeout = 60,           -- 可选,单位秒
    },
})
```

除了 `provider` 也可以直接传 `base_url`(例如自建端点)。API key 通过环境变量
传给后端,绝不经过 argv,因此不会泄漏到日志或进程列表。

`api_key` 支持多种写法,无需硬编码:

```lua
require("translator").setup({
    llm = {
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
    },
})
```

`provider` 也可写成 `name`(`name = "deepseek"`)。

### LLM 降级(主端点 + 本地兜底)

可以配置一个**降级端点** `llm.fallback`:主端点(如 DeepSeek)请求失败或无
有效结果时,后端会自动改请求降级端点。这非常适合「在线 DeepSeek 为主,
断网时本地 llama.cpp 兜底」的组合:

```lua
require("translator").setup({
    engines = { "llm" },
    llm = {
        -- 主端点:DeepSeek(在线,质量优先)
        name = "deepseek",
        env = {
            api_key = function() return os.getenv("DEEPSEEK_API_KEY") end,
        },
        schema = { model = { default = "deepseek-chat" } },

        -- 降级端点:本地 llama.cpp(断网/主端点失败时自动使用)
        fallback = {
            base_url = "http://127.0.0.1:8080/v1",
            model = "qwen2.5-7b",
            -- prompt 不设则继承主端点 prompt
        },
    },
})
```

降级触发条件:主端点返回**空结果**(所有引擎都失败时后端仍会输出合法 JSON
但 `results` 为空,这类结果不会被缓存,也不会被当作有效译文)。网络错误、
401、超时、或响应缺少内容都会触发降级。

### 本地 LLM 服务(按需启动 + 空闲回收)

当 `llm` 或 `llm.fallback` 指向本地服务(llama.cpp / llama-server)时,可以
配置 `llm.server` 让插件**自动管理服务生命周期**:

- **按需启动**:翻译前若服务未运行,插件自动拉起并异步等待就绪(不阻塞 UI)。
- **活跃标记**:每次成功翻译后写入时间戳文件。
- **空闲回收**:外部 watchdog(launchd 定时器)依据时间戳,空闲超时后自动
  停止服务,释放常驻内存。

```lua
require("translator").setup({
    llm = {
        -- ... 主端点 / fallback ...
        server = {
            cmd = {
                "/opt/homebrew/bin/llama-server",
                "-m", vim.fn.expand("~/models/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf"),
                "--alias", "qwen2.5-7b",
                "--host", "127.0.0.1",
                "--port", "8080",
                "-c", "8192",
            },
            health = "http://127.0.0.1:8080/health", -- 健康检查地址
            wait = 120,        -- 等待服务就绪的最长秒数
            poll_ms = 1000,    -- 健康检查轮询间隔(毫秒)
            stamp = vim.fn.expand("~/.cache/translator/llm.last_active"), -- 活跃时间戳
        },
    },
})
```

### 本地 LLM 安装(llama.cpp)

以 macOS 上的 **llama.cpp** 为例(其他平台同理,命令路径略有差异):

**1. 安装 llama.cpp**

```sh
brew install llama.cpp   # 提供 llama-server 二进制
```

**2. 下载模型(GGUF)**

推荐 **Qwen2.5-7B-Instruct** 的 **Q4_K_M** 量化版(~4.7GB,16GB 内存的甜点):

```sh
mkdir -p ~/models && cd ~/models
# ModelScope(国内镜像,速度快):
curl -L -C - -o qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  "https://modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/master/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf"
curl -L -C - -o qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf \
  "https://modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/master/qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf"
# 或 HuggingFace:
#   https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF
```

**3. 手动启动服务(验证用)**

```sh
llama-server \
  -m ~/models/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  --alias qwen2.5-7b --host 127.0.0.1 --port 8080 -c 8192
```

llama.cpp 会自动识别同目录下的 `-00002-of-00002.gguf` 分片,无需合并。

**4. 空闲回收 watchdog(macOS launchd)**

创建 `~/models/llm-watchdog.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail
STAMP="$HOME/.cache/translator/llm.last_active"
IDLE_TIMEOUT="${TRANSLATOR_LLM_IDLE:-600}"  # 秒,默认 10 分钟
PID_CMD="/opt/homebrew/bin/llama-server"

[ -f "$STAMP" ] || exit 0
now=$(date +%s)
last=$(stat -f%m "$STAMP" 2>/dev/null || echo "$now")
age=$((now - last))

if [ "$age" -ge "$IDLE_TIMEOUT" ] && pgrep -f "$PID_CMD" >/dev/null 2>&1; then
  echo "$(date '+%F %T') 空闲 ${age}s,停止 llama-server" >>"$HOME/models/llm-watchdog.log"
  pkill -f "$PID_CMD" || true
fi
```

然后创建 `~/Library/LaunchAgents/com.translator.llm-watchdog.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.translator.llm-watchdog</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>/Users/you/models/llm-watchdog.sh</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>StartInterval</key><integer>300</integer>
    <key>StandardOutPath</key><string>/Users/you/models/llm-watchdog.log</string>
    <key>StandardErrorPath</key><string>/Users/you/models/llm-watchdog.log</string>
</dict>
</plist>
```

加载:

```sh
chmod +x ~/models/llm-watchdog.sh
launchctl load ~/Library/LaunchAgents/com.translator.llm-watchdog.plist
```

现在服务会在翻译时按需启动,空闲 10 分钟后自动停止释放内存。

> **说明**:本地 7B 量化模型的质量无法与 DeepSeek 等在线大模型相比,建议作为
> **离线兜底**使用(即上面的 `llm.fallback` 组合),而不是唯一主力。

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

`api` 引擎与 `llm` 引擎共用 LLM 配置(即 `llm` 配置项)。它同样支持
`llm.fallback`:主端点失败时,api 引擎会改用**简化 prompt**(概述 + 若干要点)
重试降级端点——本地小模型也能稳定跟随。

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
require("translator").setup({
    source_lang = "auto",                  -- 默认源语言
    target_lang = "zh",                    -- 默认目标语言
    bilingual = false,                     -- 逐句对照显示
    engines = { "google", "youdao" },      -- 默认引擎
    proxy_url = "",                        -- 例如 "socks5://127.0.0.1:1080"
    request_timeout = 15000,               -- 后端请求超时(毫秒);<=0 不限制
    debug = false,                         -- 写入日志到数据目录

    llm = {                                -- OpenAI 兼容 LLM 配置(见上)
        -- name / base_url / api_key / model / prompt / timeout
        -- fallback = { ... },             -- 降级端点(主端点失败时自动使用)
        -- server = { ... },               -- 本地服务按需启动 + 空闲回收
    },
    baidu = {                              -- 百度开放平台凭证(支持整句翻译)
        -- appid / key,或 appid_name / key_name(环境变量名)
    },

    window = {
        type = "float",                    -- "float" | "preview"
        max_width = 999,                   -- 最大列数(999 = 不限制)
        max_height = 999,                  -- 最大行数(999 = 不限制)
    },
    cache = {
        enable = true,                     -- 缓存相同翻译结果
        ttl = 7 * 24 * 60 * 60,            -- 过期时间(秒);0 = 永不过期
    },
    history = { enable = true },           -- 持久化历史
    spinner = { enable = true },           -- 翻译时在光标处显示旋转提示
    cancel_key = "<Esc>",                  -- 中断在途翻译请求的按键
    incremental = true,                    -- 结果到达即增长浮窗
    tts = { engine = "say" },              -- "say" | "google"
    anki = { deck = "翻译", port = 8765, model = "translator" },
})
```

用 lazy.nvim 时,把同样的表放进 `opts` 即可(lazy 会自动调用 `setup(opts)`)。

### 缓存

相同请求(文本 + 语言方向 + 引擎 + LLM 模型/prompt)的结果会被缓存复用,
重复请求完全跳过后端。缓存位于 `stdpath("data")/translator/cache.json`,
最多 500 条(最旧优先淘汰),`cache.ttl` 秒后过期(默认 7 天)。

**失败/空结果不会被写入缓存**——即使所有引擎都失败(例如断网),后端仍会输出
合法 JSON 但 `results` 为空,这类结果既不入缓存,读取时发现历史脏条目也会
当作未命中丢弃并重试。因此断网失败后,联网重试不会拿到上次的空结果。

可用 `--no-cache` 单次绕过缓存,或用 `:TranslateCacheClear` 清空全部缓存。
缓存 key 包含 LLM 提供商/模型/prompt,切换模型会自动使旧条目失效。

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
      "explains": ["[感叹词] 你好;喂"]
    }
  ]
}
```

## 健康检查

```vim
:checkhealth translator
```
