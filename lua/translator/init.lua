-- File: lua/translator/init.lua

local cmdline = require("translator.cmdline")
local logger = require("translator.logger")
local job = require("translator.job")

local M = {}

local function get_python()
	-- 使用 vim.fn.executable 是 Neovim 原生方法，没问题
	-- vim.g 也是 Neovim 原生
	if vim.g.python3_host_prog and vim.fn.executable(vim.g.python3_host_prog) == 1 then
		return vim.g.python3_host_prog
	elseif vim.fn.executable("python3") == 1 then
		return "python3"
	elseif vim.fn.executable("python") == 1 then
		return "python"
	else
		vim.notify("translator.nvim: python not found", vim.log.levels.ERROR)
		return nil
	end
end

local function get_script_path()
	-- 使用 vim.fn.fnamemodify 没问题，但 debug.getinfo 不是 Neovim 特有的
	-- 改为使用 Neovim 的 API 获取脚本路径
	local current = debug.getinfo(1, "S").source:sub(2) -- 这个可以保留，因为是 Lua 标准库

	-- 方法1：使用 vim.fn.fnamemodify（已在使用）
	local root = vim.fn.fnamemodify(current, ":h:h:h")

	-- 方法2：也可以使用 vim.fs 模块（Neovim 0.8+）
	-- local root = vim.fs.dirname(vim.fs.dirname(vim.fs.dirname(current)))

	return root .. "/script/translator.py"
end

function M.start(displaymode, bang, range, line1, line2, argstr)
	logger.init()

	local options = cmdline.parse(bang, range, line1, line2, argstr)
	if not options then
		return
	end

	M.translate(options, displaymode)
end

function M.translate(options, displaymode)
	local python = get_python()
	if not python then
		return
	end

	local script = get_script_path()

	-- 构建命令表
	local cmd = {
		python,
		script,
		"--target_lang",
		options.target_lang,
		"--source_lang",
		options.source_lang,
		options.text,
		"--engines",
	}

	for _, e in ipairs(options.engines) do
		table.insert(cmd, e)
	end

	-- 使用 vim.g（Neovim 原生）
	if vim.g.translator_proxy_url and vim.g.translator_proxy_url ~= "" then
		table.insert(cmd, "--proxy")
		table.insert(cmd, vim.g.translator_proxy_url)
	end

	if vim.tbl_contains(options.engines, "trans") then
		local opts = table.concat(vim.g.translator_translate_shell_options or {}, ",")
		table.insert(cmd, "--options=" .. opts)
	end

	logger.log(table.concat(cmd, " "))

	-- 调用 job.lua
	job.jobstart(cmd, displaymode)
end

return M
