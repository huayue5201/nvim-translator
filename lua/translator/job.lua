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
-- FIXED: JSON 拼接
---------------------------------------------------------------------
local function handle_output(displaymode, data, event)
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

function M.jobstart(cmd, displaymode, env, options)
	stdout_save = nil
	current_options = options
	vim.g.translator_status = "translating"

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
	}

	if env then
		opts.env = env
	end

	vim.fn.jobstart(cmd, opts)
end

return M
