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

	vim.health.error(
		"Backend binary not found",
		"Run `make build` in the plugin directory (requires Rust/cargo)."
	)
end

---------------------------------------------------------------------
-- Check proxy (bing/google may require it)
---------------------------------------------------------------------
local function check_proxy()
	local proxy = vim.g.translator_proxy_url or ""

	if proxy == "" then
		vim.health.warn("Proxy not configured", "Bing/Google translation may fail without proxy")
	else
		vim.health.ok("Proxy configured: " .. proxy)
	end
end

---------------------------------------------------------------------
-- Main entry
---------------------------------------------------------------------
function M.check()
	vim.health.start("translator.nvim")

	check_binary()
	check_proxy()

	vim.health.ok("Neovim floating window support detected")
	vim.health.ok("Async job support detected")
end

return M
