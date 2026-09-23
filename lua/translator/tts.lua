-- File: lua/translator/tts.lua
-- Text-to-speech: speaks the source text or the translation using the Rust
-- backend's `speak` subcommand (local `say` by default, or online Google TTS).

local binary = require("translator.binary")
local util = require("translator.util")
local state = require("translator.state")

local M = {}

--- Speak a piece of text asynchronously (never blocks the UI).
function M.speak(text, lang)
	if not text or text == "" then
		return
	end

	local bin = binary.get()
	if not bin then
		return
	end

	local engine = vim.g.translator_tts_engine or "say"
	local cmd = { bin, "speak", "--text", text, "--lang", lang, "--engine", engine }

	vim.fn.jobstart(cmd, {
		stderr_buffered = true,
		on_stderr = function(_, data)
			local msg = table.concat(data or {}, "\n")
			if msg ~= "" then
				vim.notify("[translator] tts: " .. msg, vim.log.levels.ERROR)
			end
		end,
	})
end

--- `:TranslateSay` speaks the source text; `:TranslateSay!` speaks the target.
function M.say(bang, opts)
	opts = opts or { range = 0, line1 = 1, line2 = 1 }

	if bang then
		local paraphrase = state.paraphrase()
		if paraphrase == "" then
			util.show_msg("没有可朗诵的译文（先翻译一次）", "warning")
			return
		end
		M.speak(paraphrase, state.get().options.target_lang)
	else
		local text
		local lang

		local s = state.get()
		if s and s.trans and s.trans.text and s.trans.text ~= "" then
			text = s.trans.text
			lang = s.options.source_lang
		else
			text = util.get_text_from_context(opts)
			lang = vim.g.translator_source_lang or "auto"
		end

		text = util.text_proc(text)
		if text == "" then
			util.show_msg("没有可朗诵的文本", "warning")
			return
		end

		M.speak(text, lang)
	end
end

return M
