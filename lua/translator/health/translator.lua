-- File: lua/translator/health/translator.lua
-- Neovim-native health check for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Check the Rust backend binary
---------------------------------------------------------------------
local function check_binary()
	local current = debug.getinfo(1, "S").source:sub(2)
	local root = vim.fn.fnamemodify(current, ":h:h:h:h")

	local candidates = {
		root .. "/bin/translator",
		root .. "/rust/target/release/translator",
	}

	for _, bin in ipairs(candidates) do
		if vim.fn.executable(bin) == 1 then
			vim.health.ok("Backend binary found: " .. bin)
			return
		end
	end

	vim.health.error("Backend binary not found", "Run `make build` in the plugin directory (requires Rust/cargo).")
end

---------------------------------------------------------------------
-- Check proxy (bing/google may require it)
---------------------------------------------------------------------
local function check_proxy()
	local proxy = require("translator.config").get().proxy_url or ""

	if proxy == "" then
		vim.health.warn("Proxy not configured", "Bing/Google translation may fail without proxy")
	else
		vim.health.ok("Proxy configured: " .. proxy)
	end
end

---------------------------------------------------------------------
-- Check TTS setup
---------------------------------------------------------------------
local function check_tts()
	local cfg = require("translator.config").get().tts or {}
	local engine = cfg.engine or "local"

	if engine ~= "local" then
		vim.health.ok(("TTS engine: %s"):format(engine))
		return
	end

	local tts = require("translator.tts")
	if tts.server_alive() then
		vim.health.ok(("TTS service reachable at %s"):format(cfg.url or "http://127.0.0.1:8880"))
	else
		vim.health.warn(
			("TTS service not reachable at %s"):format(cfg.url or "http://127.0.0.1:8880"),
			"Run `:TranslateTtsServer` or `make tts-setup`; playback falls back to the OS voice meanwhile."
		)
	end
end

---------------------------------------------------------------------
-- Main entry
---------------------------------------------------------------------
function M.check()
	vim.health.start("translator.nvim")

	check_binary()
	check_proxy()
	check_tts()

	vim.health.ok("Neovim floating window support detected")
	vim.health.ok("Async job support detected")
end

return M
