# translator.nvim

A Neovim-native translation plugin. The backend is written in **Rust** (no
Python required); Neovim talks to it via `jobstart` using the same
`argv → stdout JSON` protocol as before.

## Requirements

- Neovim 0.8+ (0.10+ recommended; TTS and Anki features need 0.10+)
- Rust toolchain (`cargo`) — only needed once, to build the backend binary
- `curl` — for the Anki feature (bundled with macOS/Linux)

## Install

Use your favourite plugin manager, then build the backend:

```sh
# with lazy.nvim
{
  "yourname/nvim-translator",
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

| Command           | Action                                                  |
| ----------------- | ------------------------------------------------------- |
| `:Translate`      | Echo translation for the word / selection / text         |
| `:TranslateW`     | Show translation in a floating window                    |
| `:TranslateR`     | Replace the visual selection with the translation        |
| `:TranslateX`     | Translate the `*` (system clipboard) register            |
| `:TranslateSay`   | Speak the source text (`!` = speak the translation)      |
| `:TranslateA`     | Add the last translation to Anki (via AnkiConnect)       |
| `:TranslateH`     | Open the translation history                             |
| `:TranslateL`     | Open the debug log                                       |

Text source priority:

1. Explicit text after the command: `:Translate hello world`
2. Visual selection (char / line / block wise)
3. Line range: `:3,5Translate`
4. Word under cursor

Options (passed as `--key=value`):

```vim
:Translate --engines=google,youdao hello world
:Translate --target_lang=en --source_lang=zh 你好
```

A trailing `!` swaps source/target languages:

```vim
:Translate! hello     " translate zh -> en
```

## Engines

`google`, `youdao`, `baidu`, `bing`, `baicizhan`, `haici`, `iciba`,
`trans` (translate-shell CLI), `sdcv` (StarDict CLI), and `llm`
(OpenAI-compatible LLM API).

`trans` and `sdcv` shell out to external commands and must be installed
separately. Some free endpoints (`google`, `bing`, `youdao`) may require a
proxy in certain regions.

### LLM engine

One generic engine covers every OpenAI-compatible provider (DeepSeek, OpenAI,
Qwen, Kimi, Doubao, local Ollama, ...). Configure it once, then set
`llm` as your default engine:

```lua
vim.g.translator_llm = {
    provider = "deepseek",   -- preset: deepseek|openai|ollama|qwen|kimi|doubao
    api_key = "sk-...",       -- not needed for ollama
    -- model = "deepseek-chat", -- optional, preset provides a default
    -- prompt = "...",         -- optional, {sl} and {tl} are replaced
    -- timeout = 60,           -- optional, seconds
}
vim.g.translator_default_engines = { "llm" }
```

Instead of `provider` you can pass `base_url` directly (e.g. a self-hosted
endpoint). The API key is passed to the backend via an environment variable,
never via argv, so it cannot leak into logs or the process list.

`api_key` accepts several forms, so you never have to hardcode it:

```lua
vim.g.translator_llm = {
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
}
```

`provider` may also be written as `name` (`name = "deepseek"`).

## Text-to-speech (朗诵)

Speak the source text or the translation.

| Command            | Action                               |
| ------------------ | ------------------------------------ |
| `:TranslateSay`    | Speak the source text (word/sentence) |
| `:TranslateSay!`   | Speak the translation (target lang)   |

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

On first use the plugin auto-creates the deck and note type (idempotent), so
no manual Anki setup is needed. Duplicate notes (same front text) are skipped.

```lua
vim.keymap.set("n", "<localLeader>tla", "<Cmd>TranslateA<CR>", { desc = "加入 Anki" })
```

### Card fields

| Field    | Content                                  |
| -------- | ---------------------------------------- |
| Front    | source text (word / phrase / sentence)   |
| Back     | translation + dictionary explanations    |
| Phonetic | pronunciation                            |
| Example  | reserved (empty for now)                 |

### Anki config

```lua
vim.g.translator_anki_port = 8765      -- AnkiConnect port
vim.g.translator_anki_deck = "翻译"    -- deck name (auto-created)
vim.g.translator_anki_model = "translator" -- note type (auto-created)
```

## Configuration

```lua
vim.g.translator_target_lang = "zh"      -- default target language
vim.g.translator_source_lang = "auto"    -- default source language
vim.g.translator_proxy_url = ""          -- e.g. "socks5://127.0.0.1:1080"
vim.g.translator_history_enable = true   -- persist history
vim.g.translator_window_type = "float"   -- "float" | "preview"
vim.g.translator_window_max_width = 0.4  -- fraction of columns
vim.g.translator_window_max_height = 0.3 -- fraction of lines
vim.g.translator_default_engines = { "google", "youdao" }
vim.g.translator_debug = false           -- write logs to data dir

vim.g.translator_tts_engine = "say"      -- "say" | "google"
vim.g.translator_anki_deck = "翻译"      -- Anki deck name
```

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
      "explains": ["[感叹词] 你好;喂"],
      "alternative": []
    }
  ]
}
```

## Health check

```vim
:checkhealth translator
```
