-- File: lua/translator/history.lua
-- Neovim-native history module for translator.nvim

local util = require("translator.util")

local M = {}

---------------------------------------------------------------------
-- History file path
---------------------------------------------------------------------
local function history_path()
	local dir = vim.fn.stdpath("data") .. "/translator"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir .. "/history.txt"
end

local HISTORY = history_path()

---------------------------------------------------------------------
-- Format a history entry
---------------------------------------------------------------------
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
-- Save history
---------------------------------------------------------------------
function M.save(trans)
	if not vim.g.translator_history_enable then
		return
	end

	local entry = format_entry(trans.text, trans)
	if not entry then
		return
	end

	-- Read existing history
	local lines = {}
	if vim.fn.filereadable(HISTORY) == 1 then
		lines = vim.fn.readfile(HISTORY)
	end

	-- Avoid duplicates
	for _, line in ipairs(lines) do
		if line:find(vim.pesc(trans.text), 1, true) then
			return
		end
	end

	-- Append
	local f = io.open(HISTORY, "a")
	if f then
		f:write(entry .. "\n")
		f:close()
	end
end

---------------------------------------------------------------------
-- Export history
---------------------------------------------------------------------
function M.export()
	if vim.fn.filereadable(HISTORY) == 0 then
		util.show_msg("History file not found", "error")
		return
	end

	vim.cmd("tabnew " .. HISTORY)
	vim.bo.filetype = "translator_history"

	-- Simple highlight
	vim.cmd([[
    syn match TranslatorHistoryLeft /^\s*.\{1,32\}/
    syn match TranslatorHistoryRight /\s\{2,}.*$/

    hi def link TranslatorHistoryLeft Keyword
    hi def link TranslatorHistoryRight String
  ]])
end

return M
