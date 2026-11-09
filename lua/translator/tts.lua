-- File: lua/translator/tts.lua
-- Text-to-speech: speaks the source text or the translation using the Rust
-- backend's `speak` subcommand.
--
-- The default engine is `local`: an OpenAI-compatible TTS service on
-- localhost (mlx-audio + Kokoro by default). When that service is not
-- running the backend falls back to the OS voice (`say` on macOS).
-- `:TranslateTtsServer` starts/stops the local service.

local binary = require("translator.binary")
local util = require("translator.util")
local state = require("translator.state")
local config = require("translator.config")
local proc = require("translator.proc")

local M = {}

local function tts_config()
	return config.get().tts or {}
end

local function base_url()
	return (tts_config().url or "http://127.0.0.1:8880"):gsub("/+$", "")
end

--- Speak a piece of text asynchronously (never blocks the UI).
function M.speak(text, lang)
	if not text or text == "" then
		return
	end

	local bin = binary.get()
	if not bin then
		return
	end

	local cfg = tts_config()
	local engine = cfg.engine or "local"

	if engine == "local" and cfg.autostart ~= false and not M.server_alive() then
		M.start_server(true)
	end

	local cmd = {
		bin,
		"speak",
		"--text",
		text,
		"--lang",
		lang or "en",
		"--engine",
		engine,
	}

	if cfg.url and cfg.url ~= "" then
		vim.list_extend(cmd, { "--tts_url", cfg.url })
	end
	if cfg.model and cfg.model ~= "" then
		vim.list_extend(cmd, { "--tts_model", cfg.model })
	end
	if cfg.voice and cfg.voice ~= "" then
		vim.list_extend(cmd, { "--voice", cfg.voice })
	end
	if cfg.speed and tonumber(cfg.speed) and tonumber(cfg.speed) ~= 1.0 then
		vim.list_extend(cmd, { "--speed", tostring(cfg.speed) })
	end
	if cfg.fallback == false then
		vim.list_extend(cmd, { "--fallback", "false" })
	end

	proc.spawn(cmd, {}, function(res)
		local msg = vim.trim(res.stderr or "")
		if msg ~= "" then
			vim.notify("[translator] tts: " .. msg, vim.log.levels.ERROR)
		end
	end)
end

--- `:TranslateSay` speaks the source text; `:TranslateSay!` speaks the target.
function M.say(bang, opts)
	opts = opts or { range = 0, line1 = 1, line2 = 1 }

	if bang then
		local paraphrase = state.paraphrase()
		if paraphrase == "" then
			util.show_msg("No translation to speak (translate first)", "warning")
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
			lang = config.get().source_lang or "auto"
		end

		text = util.text_proc(text)
		if text == "" then
			util.show_msg("No text to speak", "warning")
			return
		end

		M.speak(text, lang)
	end
end

-- ---------------------------------------------------------------------------
-- Local TTS service lifecycle
-- ---------------------------------------------------------------------------

--- True when the local TTS service answers.
function M.server_alive()
	local url = base_url()
	local out = vim.fn.system({
		"curl",
		"-s",
		"-o",
		"/dev/null",
		"-w",
		"%{http_code}",
		"-m",
		"2",
		url .. "/",
	})
	return vim.trim(out) == "200"
end

local function server_cmd()
	local cfg = tts_config()
	if cfg.server_cmd and #cfg.server_cmd > 0 then
		return cfg.server_cmd
	end
	return { "mlx_audio.server", "--host", "127.0.0.1", "--port", "8880" }
end

local function server_env()
	local cfg = tts_config()
	local env = vim.tbl_extend("force", {}, cfg.server_env or {})
	if not env.HF_ENDPOINT and not vim.env.HF_ENDPOINT and cfg.hf_mirror ~= false then
		env.HF_ENDPOINT = "https://hf-mirror.com"
	end
	return env
end

--- Start the local TTS service in the background (idempotent).
---@return boolean ok
function M.start_server(silent)
	if M.server_alive() then
		if not silent then
			util.show_msg("TTS service already running at " .. base_url())
		end
		return true
	end

	local cmd = server_cmd()
	if vim.fn.executable(cmd[1]) ~= 1 then
		util.show_msg(
			("TTS service not found: `%s` is not installed.\nInstall it with: uv tool install mlx-audio"):format(cmd[1]),
			"error"
		)
		return false
	end

	local log = vim.fn.stdpath("cache") .. "/translator-tts.log"
	vim.fn.mkdir(vim.fn.fnamemodify(log, ":h"), "p")

	-- `stdio` file descriptors are not honoured for detached processes, so the
	-- redirection is done by an intermediate shell instead.
	local argv = { "sh", "-c", ('exec "$@" >> %s 2>&1'):format(vim.fn.shellescape(log)), "sh" }
	vim.list_extend(argv, cmd)

	vim.system(argv, { detach = true, env = server_env() }, function() end)

	-- Wait for readiness (the model itself loads on the first request).
	local ok = vim.wait(20000, function()
		return M.server_alive()
	end, 250)

	if not ok then
		util.show_msg("TTS service did not come up; see " .. log, "warning")
		return false
	end

	if not silent then
		util.show_msg("TTS service started at " .. base_url() .. " (log: " .. log .. ")")
	end
	return true
end

--- Stop the local TTS service.
function M.stop_server()
	local pkill = vim.fn.exepath("pkill")
	if pkill ~= "" then
		vim.fn.system({ pkill, "-f", "mlx_audio.server" })
	end
	util.show_msg("TTS service stopped")
end

return M
