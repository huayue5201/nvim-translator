# translator.nvim

A Neovim-native translation plugin. The backend is written in **Rust** (no
Python required); Neovim talks to it via `jobstart` using an
`argv → stdout JSON` protocol.

[中文文档](README.zh.md)

## Requirements

- Neovim 0.8+ (0.10+ recommended; TTS and Anki features need 0.10+)
- Rust toolchain (`cargo`) — only needed once, to build the backend binary
- `curl` — for the Anki feature (bundled with macOS/Linux)

## Install

Use your favourite plugin manager, then build the backend:

```sh
# with lazy.nvim
{
  "huayue5201/nvim-translator",
  build = "make build",
}
```

Or manually:

```sh
cd path/to/nvim-translator
make build
```

`make build` runs `cargo build --release` and copies the binary to
`bin/translator`.

## Usage

| Command | Action |
| ----------------- | ------------------------------------------------------- |
| `:Translate` | Echo translation for the word / selection / text |
| `:TranslateW` | Show translation in a floating window |
| `:TranslateR` | Replace the visual selection with the translation |
| `:TranslateX` | Translate the `*` (system clipboard) register |
| `:TranslateI` | Prompt for text, then translate it (interactive) |
| `:TranslateApi` | Translate a code API symbol with its documentation |
| `:TranslateSay` | Speak the source text (`!` = speak the translation) |
| `:TranslateA` | Add the last translation to Anki (via AnkiConnect) |
| `:TranslateCancel` | Abort the in-flight translation request |
| `:TranslateH` | Open the translation history |
| `:TranslateL` | Open the debug log |

Text source priority:

1. Explicit text after the command: `:Translate hello world`
2. Visual selection (char / line / block wise)
3. Line range: `:3,5Translate`
4. Word under cursor

While the translation floating window is open, a footer shows these
secondary-action keys (the window does **not** grab focus; the keys are only
mapped while the window is open and restored afterwards):

| Key | Action |
| ------ | -------------------------- |
| `s` | speak the source text |
| `S` | speak the translation |
| `a` | add to Anki (edit popup) |
| `y` | copy the translation |
| `<Esc>` | close the window |

Moving the cursor also closes the window, as before.

While a translation request is in flight, `<Esc>` aborts it (kills the backend
process and stops the spinner). The key is only bound in normal/visual mode,
only when you haven't mapped it yourself, and is removed once the request
settles. Disable it with `cancel_key = false`, or cancel explicitly with
`:TranslateCancel`.

Multi-engine results are shown **incrementally**: the floating window pops up
as soon as the **first** engine returns, then grows one section at a time as
the others arrive (in arrival order), so you never wait for the slowest source.
While requests are still pending a trailing `⏳ 还有 N 个翻译中…` line is shown
and disappears when everything is in; the window only grows, it never jumps.
Set `incremental = false` to fall back to the old all-at-once behaviour.
Applies to `:Translate` / `:TranslateI` floating windows.

Options (passed as `--key=value`):

```vim
:Translate --engines=google,youdao hello world
:Translate --target_lang=en --source_lang=zh 你好
```

A trailing `!` swaps source/target languages. It only applies when the
languages are set explicitly; with auto direction the plugin already
picks the right direction for you.

### Auto direction (双语自动互翻)

By default the plugin detects the text and picks the direction
automatically, so both directions work with no flags:

```vim
:Translate hello     " en -> zh
:Translate 你好      " zh -> en
```

- Contains CJK (Chinese / kana / Hangul) → `zh → en`
- Otherwise → `auto → zh`

Explicit `--source_lang` / `--target_lang` override the auto detection:

```vim
:Translate --source_lang=zh --target_lang=ja 你好
```

### Bilingual side-by-side (双语对照)

The window modes (`:TranslateW`, `:TranslateI`) can show the source and the
translation **sentence by sentence** instead of stacking the full translation
below the source:

```vim
:TranslateW --bilingual hello. how are you?
```

Each engine's `paraphrase` is interleaved with the source: one source
sentence followed by its translation (marked with `↳`):

```
⟦ hello. how are you? ⟧

─── google ───
  hello.
  ↳ 你好。
  how are you?
  ↳ 你好吗？
```

Dictionary-style explanations (`explains`) and phonetics are unchanged.

Enable it globally:

```lua
vim.g.translator_bilingual = true
```

and override per invocation with `--bilingual` / `--no-bilingual`.

### Interactive input

`:TranslateI` opens an input prompt prefilled with the current context
(word under cursor / visual selection / line range), so you can tweak the
text before translating. It accepts the same `--flags` and `!` as
`:Translate`:

```vim
:TranslateI                  " prompt, prefilled with <cword>
:TranslateI --engines=llm    " prompt, then translate with the llm engine
:TranslateI!                 " prompt, then translate with swapped languages
```

The result is shown in a fixed, centered floating window; the cursor moves
into it so you can select and copy the translation text. `q` / `<Esc>` /
leaving the window closes it.

## Engines

`google`, `youdao`, `baidu`, `bing`, `baicizhan`, `haici`, `iciba`,
`trans` (translate-shell CLI), `sdcv` (StarDict CLI), `llm`
(OpenAI-compatible LLM API), and `api` (API-documentation engine, see below).

`trans` and `sdcv` shell out to external commands and must be installed
separately. Some free endpoints (`google`, `bing`, `youdao`) may require a
proxy in certain regions.

### Baidu engine

`baidu` supports **full sentences** once configured with a
[Baidu Translate Open Platform](https://fanyi-api.baidu.com/) `appid` + `key`.
Without credentials it falls back to the free `/sug` dictionary endpoint, which
is **word-only** (sentences return nothing).

```lua
require("translator").setup({
    engines = { "baidu", "google" },
    baidu = {
        appid = "2024xxxxxxxxx",
        key   = "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx",
        -- or read from env-var names:
        -- appid_name = "BAIDU_APPID", key_name = "BAIDU_KEY",
    },
})
```

The official API bills by source-text character count; personal use is free
(100万 chars/month after free real-name verification).

### LLM engine

One generic engine covers every OpenAI-compatible provider (DeepSeek, OpenAI,
Qwen, Kimi, Doubao, local Ollama / llama.cpp, ...). Configure it once, then set
`llm` as your default engine:

```lua
require("translator").setup({
    engines = { "llm" },
    llm = {
        provider = "deepseek",   -- preset: deepseek|openai|ollama|qwen|kimi|doubao
        api_key = "sk-...",       -- not needed for ollama / llama.cpp
        -- model = "deepseek-chat", -- optional, preset provides a default
        -- prompt = "...",         -- optional, {sl} and {tl} are replaced
        -- timeout = 60,           -- optional, seconds
    },
})
```

Instead of `provider` you can pass `base_url` directly (e.g. a self-hosted
endpoint). The API key is passed to the backend via an environment variable,
never via argv, so it cannot leak into logs or the process list.

`api_key` accepts several forms, so you never have to hardcode it:

```lua
require("translator").setup({
    llm = {
        provider = "deepseek",
        -- 1) a string
        -- api_key = "sk-...",
        -- 2) a lazy function
        api_key = function() return os.getenv("DEEPSEEK_API_KEY") end,
        -- 3) an environment variable name
        -- api_key_name = "DEEPSEEK_API_KEY",
        -- 4) nested env form (codecompanion-style)
        -- env = { api_key = function() return os.getenv("DEEPSEEK_API_KEY") end },
        model = "deepseek-chat",
        -- codecompanion-style model default is also accepted:
        -- schema = { model = { default = "deepseek-chat" } },
    },
})
```

`provider` may also be written as `name` (`name = "deepseek"`).

### LLM fallback (primary endpoint + local failover)

Configure a **fallback endpoint** via `llm.fallback`: when the primary
endpoint (e.g. DeepSeek) fails or returns no usable result, the backend
automatically retries against the fallback. This is ideal for
"online DeepSeek as primary, local llama.cpp as an offline safety net":

```lua
require("translator").setup({
    engines = { "llm" },
    llm = {
        -- primary: DeepSeek (online, quality-first)
        name = "deepseek",
        env = {
            api_key = function() return os.getenv("DEEPSEEK_API_KEY") end,
        },
        schema = { model = { default = "deepseek-chat" } },

        -- fallback: local llama.cpp (used automatically on failure)
        fallback = {
            base_url = "http://127.0.0.1:8080/v1",
            model = "qwen2.5-7b",
            -- omit prompt to inherit the primary prompt
        },
    },
})
```

Fallback triggers when the primary endpoint returns **no usable result** (a
network error, 401, timeout, or a response without content). Empty results are
never cached, so a failed request is never served again from the cache.

### Local LLM server (on-demand start + idle recycling)

When `llm` or `llm.fallback` points at a local server (llama.cpp /
llama-server), `llm.server` lets the plugin manage its lifecycle:

- **On-demand start**: before translating, the plugin starts the server if it
  is not running and waits asynchronously (no UI freeze).
- **Activity marker**: every successful translation writes a timestamp file.
- **Idle recycling**: an external watchdog (launchd timer) stops the server
  after an idle timeout, releasing resident memory.

```lua
require("translator").setup({
    llm = {
        -- ... primary / fallback ...
        server = {
            cmd = {
                "/opt/homebrew/bin/llama-server",
                "-m", vim.fn.expand("~/models/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf"),
                "--alias", "qwen2.5-7b",
                "--host", "127.0.0.1",
                "--port", "8080",
                "-c", "8192",
            },
            health = "http://127.0.0.1:8080/health", -- health-check URL
            wait = 120,        -- max seconds to wait for readiness
            poll_ms = 1000,    -- health-check poll interval (ms)
            stamp = vim.fn.expand("~/.cache/translator/llm.last_active"), -- activity stamp
        },
    },
})
```

### Installing a local LLM (llama.cpp)

Example for **llama.cpp** on macOS (other platforms are analogous):

**1. Install llama.cpp**

```sh
brew install llama.cpp   # provides the llama-server binary
```

**2. Download a GGUF model**

**Qwen2.5-7B-Instruct** in **Q4_K_M** (~4.7GB, the sweet spot for 16GB RAM)
is recommended:

```sh
mkdir -p ~/models && cd ~/models
# ModelScope (fast mirror):
curl -L -C - -o qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  "https://modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/master/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf"
curl -L -C - -o qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf \
  "https://modelscope.cn/models/Qwen/Qwen2.5-7B-Instruct-GGUF/resolve/master/qwen2.5-7b-instruct-q4_k_m-00002-of-00002.gguf"
# or HuggingFace:
#   https://huggingface.co/Qwen/Qwen2.5-7B-Instruct-GGUF
```

**3. Start the server manually (to verify)**

```sh
llama-server \
  -m ~/models/qwen2.5-7b-instruct-q4_k_m-00001-of-00002.gguf \
  --alias qwen2.5-7b --host 127.0.0.1 --port 8080 -c 8192
```

llama.cpp auto-discovers the `-00002-of-00002.gguf` shard in the same
directory; no merge step is needed.

**4. Idle-recycling watchdog (macOS launchd)**

Create `~/models/llm-watchdog.sh`:

```sh
#!/usr/bin/env bash
set -euo pipefail
STAMP="$HOME/.cache/translator/llm.last_active"
IDLE_TIMEOUT="${TRANSLATOR_LLM_IDLE:-600}"  # seconds, default 10 min
PID_CMD="/opt/homebrew/bin/llama-server"

[ -f "$STAMP" ] || exit 0
now=$(date +%s)
last=$(stat -f%m "$STAMP" 2>/dev/null || echo "$now")
age=$((now - last))

if [ "$age" -ge "$IDLE_TIMEOUT" ] && pgrep -f "$PID_CMD" >/dev/null 2>&1; then
  echo "$(date '+%F %T') idle ${age}s, stopping llama-server" >>"$HOME/models/llm-watchdog.log"
  pkill -f "$PID_CMD" || true
fi
```

Then create `~/Library/LaunchAgents/com.translator.llm-watchdog.plist`:

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

Load it:

```sh
chmod +x ~/models/llm-watchdog.sh
launchctl load ~/Library/LaunchAgents/com.translator.llm-watchdog.plist
```

The server now starts on demand and stops after 10 idle minutes, freeing
memory.

> **Note**: a local 7B quantised model cannot match the quality of online
> models such as DeepSeek; prefer it as an **offline fallback** (the
> `llm.fallback` combo above) rather than the sole engine.

## API documentation translation

Because most translation in a code editor happens over code, the `api` engine
(and the `:TranslateApi` command) translate a code symbol **together with its
documentation** instead of doing a plain dictionary lookup.

```vim
:TranslateApi                          " word under cursor
:TranslateApi requests.get             " explicit symbol
:TranslateApi --target_lang=en map     " explicit target language
```

How it works:

1. The current buffer's `filetype` is used as the programming-language hint
   (e.g. `python`, `rust`, `javascript`).
2. The symbol is sent to the configured LLM with an API-documentation prompt.
3. The model decides whether the input is an API; if it is not (a plain word,
   for example), it falls back to a normal translation.

Output sections (only the applicable ones are shown):

| Section | Content |
| -------- | --------------------------------------------------- |
| Summary | one-sentence description of what the API does (translated) |
| Signature | exact signature / call form (kept verbatim) |
| Parameters | parameter descriptions (translated) |
| Returns | return value description (translated) |
| Example | short usage example (code kept verbatim) |
| Notes | deprecation / version / caveats (translated) |

Code, signatures, identifiers and parameter names are always kept verbatim;
only human-language descriptions are translated.

The `api` engine shares the LLM configuration with the `llm` engine, so it
requires the `llm` config option (see above). It also honours `llm.fallback`:
when the primary endpoint fails, the api engine retries the fallback endpoint
with a simplified prompt (a summary plus short bullet points) that small local
models can follow reliably.

Suggested keymaps:

```lua
vim.keymap.set("n", "<localLeader>tld", "<Cmd>TranslateApi<CR>", { desc = "API 文档翻译" })
vim.keymap.set("v", "<localLeader>tld", ":TranslateApi<CR>", { desc = "API 文档翻译" })
```

## Text-to-speech (朗诵)

Speak the source text or the translation.

| Command | Action |
| ------------------ | ------------------------------------ |
| `:TranslateSay` | Speak the source text (word/sentence) |
| `:TranslateSay!` | Speak the translation (target lang) |

`TranslateSay` speaks the **last translated text** (or, if you haven't
translated yet, the word under cursor / visual selection). `TranslateSay!`
speaks the translation in the target language.

### TTS engines

```lua
vim.g.translator_tts_engine = "say"   -- "say" (local, default) | "google" (online)
```

- **`say` (default)** — uses the OS's built-in TTS, no network, no extra
  dependencies:
  - macOS: `say` (built in, has en_US + zh_CN voices)
  - Linux: `espeak-ng` / `espeak` / `spd-say` (install one, e.g.
    `sudo apt install espeak-ng`)
  - Windows: PowerShell `System.Speech`
- **`google`** — online Google TTS, more natural voices, requires network and
  an audio player:
  - macOS: `afplay` (built in)
  - Linux: `mpv` / `ffplay` / `aplay`
  - Windows: PowerShell `SoundPlayer`

Example keymaps:

```lua
vim.keymap.set("n", "<localLeader>tls", "<Cmd>TranslateSay<CR>", { desc = "读原文" })
vim.keymap.set("n", "<localLeader>tlt", "<Cmd>TranslateSay!<CR>", { desc = "读译文" })
```

## Anki cards (背单词)

Add the last translation to Anki through
[AnkiConnect](https://git.sr.ht/~foosoft/anki-connect).

### Dependencies

1. Install [Anki](https://apps.ankiweb.net/).
2. In Anki: **Tools → Add-ons → Get Add-ons…**, enter code `2055492159`
   (AnkiConnect), restart Anki.
3. Keep Anki running while using this feature (AnkiConnect listens on
   `127.0.0.1:8765`).

### Usage

Translate a word/sentence first, then run `:TranslateA` (or map it to a key):

```vim
:Translate naive
:TranslateA
```

`:TranslateA` opens an edit popup prefilled with the translation, so you can
tweak each field before saving:

| Key | Action |
| ---------------- | ---------------------- |
| `<Tab>`/`<S-Tab>` | switch field |
| `<Up>`/`<Down>` | browse field history |
| `<CR>` | save to Anki |
| `q` / `<Esc>` | cancel |

On first use the plugin auto-creates the deck and note type (idempotent), so
no manual Anki setup is needed. Duplicate notes (same front text) are skipped.

```lua
vim.keymap.set("n", "<localLeader>tla", "<Cmd>TranslateA<CR>", { desc = "加入 Anki" })
```

### Card fields

| Field | Content |
| -------- | ---------------------------------------- |
| Front | source text (word / phrase / sentence) |
| Back | translation + dictionary explanations |
| Phonetic | pronunciation |
| Example | reserved (empty for now) |

### Anki config

```lua
vim.g.translator_anki_port = 8765      -- AnkiConnect port
vim.g.translator_anki_deck = "翻译"    -- deck name (auto-created)
vim.g.translator_anki_model = "translator" -- note type (auto-created)
```

## Configuration

```lua
require("translator").setup({
    source_lang = "auto",                  -- default source language
    target_lang = "zh",                    -- default target language
    bilingual = false,                     -- sentence-by-sentence view
    engines = { "google", "youdao" },      -- default engines
    proxy_url = "",                        -- e.g. "socks5://127.0.0.1:1080"
    request_timeout = 15000,               -- backend request timeout (ms); <=0 = no limit
    debug = false,                         -- write logs to data dir

    llm = {                                -- OpenAI-compatible LLM config (see above)
        -- name / base_url / api_key / model / prompt / timeout
        -- fallback = { ... },             -- failover endpoint (used on primary failure)
        -- server = { ... },               -- on-demand start + idle recycling
    },
    baidu = {                              -- Baidu Open Platform creds (sentence support)
        -- appid / key, or appid_name / key_name (env-var names)
    },

    window = {
        type = "float",                    -- "float" | "preview"
        max_width = 999,                   -- max columns (999 = no limit)
        max_height = 999,                  -- max lines (999 = no limit)
    },
    cache = {
        enable = true,                     -- reuse identical translations
        ttl = 7 * 24 * 60 * 60,            -- expiry seconds; 0 = never expire
    },
    history = { enable = true },           -- persist history
    spinner = { enable = true },           -- cursor spinner while translating
    cancel_key = "<Esc>",                  -- key that aborts an in-flight request
    incremental = true,                    -- grow the window as results arrive
    tts = { engine = "say" },              -- "say" | "google"
    anki = { deck = "翻译", port = 8765, model = "translator" },
})
```

With lazy.nvim the same table goes in `opts` (lazy calls `setup(opts)` for
you).

### Cache

Identical requests (text + languages + engines + LLM model/prompt) are cached
and reused, skipping the backend entirely. The cache lives at
`stdpath("data")/translator/cache.json`, holds at most 500 entries (oldest
evicted first), and expires after `cache.ttl` seconds (default 7 days).

**Failed/empty results are never cached** — if every engine fails (e.g. no
network), the backend still emits valid JSON but with an empty `results`; such
a result is neither cached nor treated as a valid hit, and any stale empty
entry found on read is discarded and retried. So a retry after reconnecting
never serves the previous empty result.

Use `--no-cache` to bypass the cache once, or `:TranslateCacheClear` to drop
it entirely. Cache keys include the LLM provider/model/prompt, so switching
models automatically misses old entries.

## Documentation

`:help translator` — full Vim help document (`doc/translator.txt`).

## Development

```sh
make build   # cargo build --release && install to bin/
make test    # cargo test (offline unit tests for response parsers)
make clean
```

The backend is a single crate under `rust/`. Each engine lives in
`rust/src/engines/` and returns a JSON object on stdout:

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

## Health check

```vim
:checkhealth translator
```
