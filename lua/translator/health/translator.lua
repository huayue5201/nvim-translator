-- FileName: health.lua
-- FilePath: lua/health/translator.lua
-- Description: Health check module for translator plugin

local M = {}

local function check_job()
	if vim.fn.has("nvim") == 1 then
		-- Neovim 总是有 job 功能
		vim.health.ok("Async job support detected")
	elseif vim.fn.exists("*job_start") == 1 then
		vim.health.ok("Async job support detected (Vim)")
	else
		vim.health.error("Job feature is required but not found")
	end
end

local function check_floating_window()
	-- 检查是否有 nvim_open_win 函数
	if vim.fn.exists("*nvim_open_win") == 0 then
		vim.health.error(
			"Floating window is missing in current Neovim version",
			"Upgrade your Neovim to a newer version"
		)
		return
	end

	-- 检查浮动窗口参数是否匹配（旧版本可能有不同参数）
	local success, result = pcall(function()
		local buf = vim.api.nvim_get_current_buf()
		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			row = 0,
			col = 0,
			width = 1,
			height = 1,
		})
		vim.api.nvim_win_close(win, true)
	end)

	if not success then
		vim.health.error("Floating window API is outdated", "Upgrade your Neovim to a newer version")
		return
	end

	vim.health.ok("Floating window support detected")
end

local function check_python()
	local python_exe = nil

	-- 检查用户配置的 python3_host_prog
	if vim.g.python3_host_prog and vim.fn.executable(vim.g.python3_host_prog) == 1 then
		python_exe = vim.g.python3_host_prog
	elseif vim.fn.executable("python3") == 1 then
		python_exe = "python3"
	elseif vim.fn.executable("python") == 1 then
		python_exe = "python"
	else
		vim.health.error("Python is required but not found")
		return
	end

	-- 检查 Python 版本
	local handle = io.popen(python_exe .. " --version 2>&1")
	if handle then
		local result = handle:read("*a")
		handle:close()
		if result and result:match("Python 3") then
			vim.health.ok("Using " .. python_exe .. " (" .. result:gsub("\n", "") .. ")")
		else
			vim.health.warn("Python 2 detected, Python 3 is recommended")
		end
	else
		vim.health.ok("Using " .. python_exe)
	end

	-- 检查必要的 Python 包
	local check_script = [[
import sys
try:
    import requests
    print('requests: OK')
except ImportError:
    print('requests: Missing')
]]

	local cmd = string.format('%s -c "%s"', python_exe, check_script:gsub('"', '\\"'))
	local handle2 = io.popen(cmd)
	if handle2 then
		local result = handle2:read("*a")
		handle2:close()
		if result:find("requests: OK") then
			vim.health.ok("Python requests module installed")
		else
			vim.health.warn("Python requests module not found", "Install with: pip install requests")
		end
	end
end

function M.check()
	vim.health.start("translator.nvim")

	check_job()
	check_floating_window()
	check_python()
end

return M
