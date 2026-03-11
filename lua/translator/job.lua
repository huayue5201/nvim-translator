-- File: lua/translator/job.lua
-- Lua rewrite of job.vim

local logger = require("translator.logger")
local action = require("translator.action")
local history = require("translator.history")
local util = require("translator.util")

local M = {}

-- 缓存 stdout（用于 stderr fallback）
local stdout_save = nil

---------------------------------------------------------------------
-- 清理 Python 输出（去掉 u"xxx"，处理 \uXXXX）
---------------------------------------------------------------------
local function clean_message(msg)
	if not msg or msg == "" then
		return ""
	end

	-- 去掉 Python2 的 u"xxx"
	msg = msg:gsub('(:%s*[%[{])u(")', "%1%2")
	msg = msg:gsub("(:%s*[%[{])u(')", "%1%2")

	-- 转换 \uXXXX → UTF-8
	msg = msg:gsub("\\u(%x%x%x%x)", function(hex)
		local n = tonumber(hex, 16)
		if n < 0x80 then
			return string.char(n)
		elseif n < 0x800 then
			return string.char(0xC0 + math.floor(n / 0x40), 0x80 + (n % 0x40))
		else
			return string.char(0xE0 + math.floor(n / 0x1000), 0x80 + (math.floor(n / 0x40) % 0x40), 0x80 + (n % 0x40))
		end
	end)

	return msg
end

---------------------------------------------------------------------
-- 处理 stdout / stderr
---------------------------------------------------------------------
local function handle_output(displaymode, data, event)
	if not data then
		return
	end

	-- Neovim 返回 list，需要拼接
	local message = table.concat(data, " ")
	if util.safe_trim(message) == "" then
		return
	end

	logger.log(message)

	message = clean_message(message)
	logger.log(message)

	if event == "stdout" then
		local ok, translations = pcall(vim.json.decode, message)
		if not ok or not translations then
			util.show_msg("Translation failed", "error")
			return
		end

		stdout_save = translations

		if displaymode == "echo" then
			action.echo(translations)
		elseif displaymode == "window" then
			action.window(translations)
		else
			action.replace(translations)
		end

		history.save(translations)
	elseif event == "stderr" then
		util.show_msg(message, "error")

		if stdout_save and displaymode == "echo" then
			action.echo(stdout_save)
		end
	end
end

---------------------------------------------------------------------
-- 启动 Python 进程
---------------------------------------------------------------------
function M.jobstart(cmd, displaymode)
	stdout_save = nil
	vim.g.translator_status = "translating"

	vim.fn.jobstart(cmd, {
		stdout_buffered = true,
		stderr_buffered = true,

		on_stdout = function(_, data)
			vim.g.translator_status = ""
			handle_output(displaymode, data, "stdout")
		end,

		on_stderr = function(_, data)
			vim.g.translator_status = ""
			handle_output(displaymode, data, "stderr")
		end,
	})
end

return M
