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
	local text = trans.text
	if #text > 40 then
		text = text:sub(1, 40) .. "..."
	end

	local chunks = {
		{ text, "Function" },
		{ " ==> ", "Constant" },
	}

	-- Show every engine that returned content, separated by a divider.
	local first = true
	for _, t in ipairs(trans.results) do
		local has_content = (t.paraphrase and t.paraphrase ~= "")
			or (t.explains and #t.explains > 0)
			or (t.phonetic and t.phonetic ~= "")

		if has_content then
			if not first then
				table.insert(chunks, { " │ ", "Comment" })
			end
			first = false

			table.insert(chunks, { "[" .. t.engine .. "] ", "Identifier" })

			if t.phonetic and t.phonetic ~= "" then
				table.insert(chunks, { "[" .. t.phonetic .. "] ", "Type" })
			end
			if t.paraphrase and t.paraphrase ~= "" then
				table.insert(chunks, { t.paraphrase .. " ", "Normal" })
			end
			if t.explains and #t.explains > 0 then
				table.insert(chunks, { table.concat(t.explains, " "), "Normal" })
			end
		end
	end

	vim.api.nvim_echo(chunks, false, {})
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
	local mode = vim.api.nvim_get_mode().mode
	local start
	local finish

	if mode:match("^[vV\22]") then
		start = vim.fn.getpos("v")
		finish = vim.fn.getpos(".")
	else
		start = vim.fn.getpos("'<")
		finish = vim.fn.getpos("'>")
	end

	if start[2] == 0 or finish[2] == 0 then
		util.show_msg("No visual selection to replace", "warning")
		return
	end

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
