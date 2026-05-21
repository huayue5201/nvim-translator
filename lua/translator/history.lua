-- File: lua/translator/history.lua

local util = require("translator.util")

local M = {}

local function history_path()
	local dir = vim.fn.stdpath("data") .. "/translator"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir .. "/history.txt"
end

local HISTORY = history_path()

local function format_entry(text, trans)
	local left = text
	if #left > 30 then
		left = left:sub(1, 30) .. "..."
	end

	local right = nil

	for _, t in ipairs(trans.results) do
		if t.explains and #t.explains > 0 then
			right = t.explains[1]
			break
		elseif t.paraphrase and t.paraphrase ~= "" then
			right = t.paraphrase
			break
		end
	end

	if not right then
		return nil
	end

	return string.format("%-32s %s", left, right)
end

---------------------------------------------------------------------
-- FIXED: 只检查最后 50 条
---------------------------------------------------------------------
function M.save(trans)
	if not vim.g.translator_history_enable then
		return
	end

	local entry = format_entry(trans.text, trans)

	if not entry then
		return
	end

	local lines = {}

	if vim.fn.filereadable(HISTORY) == 1 then
		lines = vim.fn.readfile(HISTORY)
	end

	local start = math.max(1, #lines - 50)

	for i = start, #lines do
		if lines[i]:find(trans.text, 1, true) then
			return
		end
	end

	local f = io.open(HISTORY, "a")
	if f then
		f:write(entry .. "\n")
		f:close()
	end
end

function M.export()
	if vim.fn.filereadable(HISTORY) == 0 then
		util.show_msg("History file not found", "error")
		return
	end

	vim.cmd("tabnew " .. HISTORY)
	vim.bo.filetype = "translator_history"
end

return M
