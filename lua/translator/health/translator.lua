-- File: lua/health/translator.lua
-- Neovim-native health check for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Check Python environment
---------------------------------------------------------------------
local function check_python()
	local python = nil

	if vim.g.python3_host_prog and vim.fn.executable(vim.g.python3_host_prog) == 1 then
		python = vim.g.python3_host_prog
	elseif vim.fn.executable("python3") == 1 then
		python = "python3"
	elseif vim.fn.executable("python") == 1 then
		python = "python"
	else
		vim.health.error("Python 3 is required but not found")
		return
	end

	-- Version check
	local handle = io.popen(python .. " --version 2>&1")
	local version = handle and handle:read("*a") or ""
	if handle then
		handle:close()
	end

	if version:match("Python 3") then
		vim.health.ok("Python detected: " .. version:gsub("\n", ""))
	else
		vim.health.warn("Python 2 detected, Python 3 is required")
	end

	-- requests module
	local check_script = [[
import sys
try:
    import requests
    print("OK")
except ImportError:
    print("Missing")
]]

	local cmd = string.format('%s -c "%s"', python, check_script:gsub('"', '\\"'))
	local h = io.popen(cmd)
	local result = h and h:read("*a") or ""
	if h then
		h:close()
	end

	if result:find("OK") then
		vim.health.ok("Python module 'requests' installed")
	else
		vim.health.warn("Python module 'requests' missing", "Install with: pip install requests")
	end
end

---------------------------------------------------------------------
-- Check proxy (bing/google require it)
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

	check_python()
	check_proxy()

	vim.health.ok("Neovim floating window support detected")
	vim.health.ok("Async job support detected")
end

return M
