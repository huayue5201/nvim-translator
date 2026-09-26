-- File: lua/translator/job.lua

local logger = require("translator.logger")
local action = require("translator.action")
local history = require("translator.history")
local util = require("translator.util")
local state = require("translator.state")

local M = {}

local stdout_save = nil
local current_options = nil

---------------------------------------------------------------------
-- Handle buffered job output (stdout carries the JSON result).
---------------------------------------------------------------------
local function handle_output(displaymode, data, event)
	-- 任何输出到达都说明请求已有响应，停止旋转提示。
	require("translator.spinner").close()

	if not data then
		return
	end

	local message = table.concat(data, "\n")

	if util.safe_trim(message) == "" then
		return
	end

	logger.log(message)

	if event == "stdout" then
		local ok, translations = pcall(vim.json.decode, message)

		if not ok or not translations then
			util.show_msg("Translation failed", "error")
			return
		end

		stdout_save = translations
		state.set(translations, current_options)

		if displaymode == "echo" then
			action.echo(translations)
		elseif displaymode == "window" then
			action.window(translations, current_options)
		elseif displaymode == "interactive" then
			action.interactive(translations, current_options)
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

function M.jobstart(cmd, displaymode, env, options)
	stdout_save = nil
	current_options = options
	vim.g.translator_status = "translating"

	-- 请求延时期间在光标处显示旋转提示（可用 vim.g.translator_spinner 关闭）。
	if vim.g.translator_spinner ~= false then
		require("translator.spinner").start()
	end

	local opts = {
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

		on_exit = function()
			require("translator.spinner").close()
		end,
	}

	if env then
		opts.env = env
	end

	vim.fn.jobstart(cmd, opts)
end

return M
