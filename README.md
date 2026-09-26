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
requires `vim.g.translator_llm` (see above).

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
vim.g.translator_target_lang = "zh"      -- default target language
vim.g.translator_source_lang = "auto"    -- default source language
vim.g.translator_proxy_url = ""          -- e.g. "socks5://127.0.0.1:1080"
vim.g.translator_history_enable = true   -- persist history
vim.g.translator_window_type = "float"   -- "float" | "preview"
vim.g.translator_window_max_width = 0.4  -- fraction of columns
vim.g.translator_window_max_height = 0.3 -- fraction of lines
vim.g.translator_bilingual = false       -- sentence-by-sentence view
vim.g.translator_spinner = true          -- cursor spinner while translating
vim.g.translator_default_engines = { "google", "youdao" }
vim.g.translator_debug = false           -- write logs to data dir

vim.g.translator_tts_engine = "say"      -- "say" | "google"
vim.g.translator_anki_deck = "翻译"      -- Anki deck name
```

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
