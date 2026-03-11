-- FileName: job.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Job control module for translator plugin

local util = require("translator.util")
local logger = require("translator.logger")
local action = require("translator.action")
local history = require("translator.history")

local M = {}

-- 存储 stdout 数据
local stdout_save = {}

-- 设置全局状态
vim.g.translator_status = ""

-- 内部处理函数
local function handle_output(type, data, event)
	vim.g.translator_status = ""

	-- Nvim 返回的是 table，拼接成字符串
	local message
	if type(data) == "table" then
		message = table.concat(data, " ")
	else
		message = data
	end

	-- 在 Nvim 中，这个函数会被执行两次，第一次返回数据，第二次返回空字符串
	-- 检查数据值以防止重复处理
	if util.safe_trim(message) == "" then
		return
	end
	logger.log(message)

	-- 1. 移除字符串前的 'u'
	message = string.gsub(message, '(: |: [|{])(u)(")', "%1%3")
	message = string.gsub(message, "(: |: [|{])(u)(')", "%1%3")
	message = string.gsub(message, "(: |: [])(u)(')", "%1%3")

	-- 2. 将 hex code 转换为普通字符
	message = string.gsub(message, "\\u(%x%x%x%x)", function(hex)
		return vim.fn.nr2char(tonumber("0x" .. hex))
	end)

	logger.log(message)

	if event == "stdout" then
		-- 解析返回的数据
		local load, result = pcall(vim.fn.eval, message)
		if not load then
			util.show_msg("Failed to parse translation result", "error")
			return
		end
		local translations = result

		if type(translations) ~= "table" or not translations["status"] then
			util.show_msg("Translation failed", "error")
			return
		end

		stdout_save = translations

		-- 根据类型执行不同动作
		if type == "echo" then
			action.echo(translations)
		elseif type == "window" then
			action.window(translations)
		else -- 'replace'
			action.replace(translations)
		end

		-- 保存到历史记录
		history.save(translations)
	elseif event == "stderr" then
		util.show_msg(message, "error")
		if not vim.tbl_isempty(stdout_save) and type == "echo" then
			action.echo(stdout_save)
		end
	end
end

-- Neovim 的 stdout/stderr 回调
local function on_stdout_nvim(type, job_id, data, event)
	handle_output(type, data, event)
end

-- Neovim 的 exit 回调
local function on_exit_nvim(job_id, code, event)
	-- 保持空函数，与原始行为一致
end

function M.jobstart(cmd, job_type)
	vim.g.translator_status = "translating"
	stdout_save = {}

	if vim.fn.has("nvim") == 1 then
		-- Neovim 的 jobstart
		local callback = {
			on_stdout = function(job_id, data, event)
				on_stdout_nvim(job_type, job_id, data, "stdout")
			end,
			on_stderr = function(job_id, data, event)
				on_stdout_nvim(job_type, job_id, data, "stderr")
			end,
			on_exit = on_exit_nvim,
		}

		vim.fn.jobstart(cmd, callback)
	else
		-- 由于你用的是 Neovim，这里只保留一个错误提示
		util.show_msg("Vim is not supported in this Lua version", "error")
	end
end

return M
