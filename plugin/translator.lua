-- File: plugin/translator.lua
-- Description: Main plugin file for translator.nvim (Neovim-native)

if vim.g.loaded_translator then
	return
end
vim.g.loaded_translator = 1

---------------------------------------------------------------------
-- Default settings
---------------------------------------------------------------------
vim.g.translator_history_enable = vim.g.translator_history_enable or false
vim.g.translator_proxy_url = vim.g.translator_proxy_url or ""
vim.g.translator_source_lang = vim.g.translator_source_lang or "auto"
vim.g.translator_target_lang = vim.g.translator_target_lang or "zh"

vim.g.translator_window_max_width = vim.g.translator_window_max_width or 999
vim.g.translator_window_max_height = vim.g.translator_window_max_height or 999
vim.g.translator_window_type = vim.g.translator_window_type or "float"

-- 双语对照显示（原文一句 / 译文一句交错），默认关闭
vim.g.translator_bilingual = vim.g.translator_bilingual or false

-- 翻译请求进行中时，在光标处显示旋转提示（默认开启）
vim.g.translator_spinner = vim.g.translator_spinner or true

-- LLM config: { provider|base_url, api_key, model, prompt?, timeout? }
-- Preset providers: deepseek, openai, ollama, qwen, kimi, doubao
vim.g.translator_llm = vim.g.translator_llm or {}

-- TTS: "say" (local, default) or "google" (online)
vim.g.translator_tts_engine = vim.g.translator_tts_engine or "say"

-- Anki (via AnkiConnect)
vim.g.translator_anki_port = vim.g.translator_anki_port or 8765
vim.g.translator_anki_deck = vim.g.translator_anki_deck or "翻译"
vim.g.translator_anki_model = vim.g.translator_anki_model or "translator"

if vim.g.translator_target_lang:match("zh") then
	vim.g.translator_default_engines = vim.g.translator_default_engines
		or {
			"bing",
			"google",
			"haici",
			"youdao",
		}
else
	vim.g.translator_default_engines = vim.g.translator_default_engines or { "google" }
end

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------
local function run_translate(displaymode, opts)
	require("translator").start(displaymode, opts)
end

vim.api.nvim_create_user_command("Translate", function(opts)
	run_translate("echo", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateW", function(opts)
	run_translate("window", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateR", function(opts)
	run_translate("replace", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateX", function(opts)
	local clipboard = vim.fn.getreg("*")
	local args = vim.trim((opts.args or "") .. " " .. clipboard)
	require("translator").start("echo", {
		bang = opts.bang,
		range = 0,
		line1 = 1,
		line2 = 1,
		args = args,
	})
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("TranslateI", function(opts)
	require("translator.input").prompt(opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateH", function()
	require("translator.history").export()
end, {})

vim.api.nvim_create_user_command("TranslateL", function()
	require("translator.logger").open_log()
end, {})

vim.api.nvim_create_user_command("TranslateSay", function(opts)
	require("translator.tts").say(opts.bang, opts)
end, { bang = true, range = true })

vim.api.nvim_create_user_command("TranslateA", function()
	require("translator.anki").add()
end, {})

vim.api.nvim_create_user_command("TranslateApi", function(opts)
	require("translator").translate_api({
		range = opts.range,
		line1 = opts.line1,
		line2 = opts.line2,
		args = opts.args,
	})
end, { nargs = "*", range = true })
