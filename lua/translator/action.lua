-- File: lua/translator/action.lua
-- Modern Neovim-native action module

local util = require("translator.util")
local logger = require("translator.logger")
local window = require("translator.window")

local M = {}

local MARK = "• "

---------------------------------------------------------------------
-- Build window content
---------------------------------------------------------------------
local function build_window_content(trans)
	local out = {}

	-- 原文（自动截断）
	local text = trans.text
	if #text > 60 then
		text = text:sub(1, 60) .. "..."
	end
	table.insert(out, "⟦ " .. text .. " ⟧")

	for _, t in ipairs(trans.results) do
		local has_content = (t.paraphrase and t.paraphrase ~= "") or (t.explains and #t.explains > 0)

		if has_content then
			table.insert(out, "")
			table.insert(out, "─── " .. t.engine .. " ───")

			if t.phonetic and t.phonetic ~= "" then
				table.insert(out, MARK .. "[" .. t.phonetic .. "]")
			end

			if t.paraphrase and t.paraphrase ~= "" then
				for line in t.paraphrase:gmatch("[^\n]+") do
					table.insert(out, MARK .. util.safe_trim(line))
				end
			end

			if t.explains then
				for _, e in ipairs(t.explains) do
					local trimmed = util.safe_trim(e)
					if trimmed ~= "" then
						table.insert(out, MARK .. trimmed)
					end
				end
			end
		end
	end

	return out
end

---------------------------------------------------------------------
-- Window display
---------------------------------------------------------------------
function M.window(trans)
	local content = build_window_content(trans)
	logger.log(content)
	window.open(content)
end

---------------------------------------------------------------------
-- Echo display
---------------------------------------------------------------------
function M.echo(trans)
	local phonetic = ""
	local paraphrase = ""
	local explains = ""

	for _, t in ipairs(trans.results) do
		if phonetic == "" and t.phonetic and t.phonetic ~= "" then
			phonetic = "[" .. t.phonetic .. "]"
		end
		if paraphrase == "" and t.paraphrase and t.paraphrase ~= "" then
			paraphrase = t.paraphrase
		end
		if explains == "" and t.explains and #t.explains > 0 then
			explains = table.concat(t.explains, " ")
		end
	end

	local text = trans.text
	if #text > 40 then
		text = text:sub(1, 40) .. "..."
	end

	util.echo("Function", text)
	util.echon("Constant", "==>")
	if phonetic ~= "" then
		util.echon("Type", phonetic)
	end
	if paraphrase ~= "" then
		util.echon("Normal", paraphrase)
	end
	if explains ~= "" then
		util.echon("Normal", explains)
	end
end

---------------------------------------------------------------------
-- Replace selected text
---------------------------------------------------------------------
function M.replace(trans)
	local replacement = nil

	for _, t in ipairs(trans.results) do
		if t.paraphrase and t.paraphrase ~= "" then
			replacement = t.paraphrase
			break
		end
	end

	if not replacement then
		util.show_msg("No paraphrase available for replacement", "warning")
		return
	end

	-- 使用 Neovim 原生 API 替换选区
	local mode = vim.fn.visualmode()
	local start = vim.fn.getpos("'<")
	local finish = vim.fn.getpos("'>")

	local srow = start[2] - 1
	local scol = start[3] - 1
	local erow = finish[2] - 1
	local ecol = finish[3] - 1 -- ← 修复这里

	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end

	local lines = vim.split(replacement, "\n")

	vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol + 1, lines)
end

return M
