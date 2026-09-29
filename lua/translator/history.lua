-- File: lua/translator/history.lua

local util = require("translator.util")
local config = require("translator.config")

local M = {}

local function history_path()
	local dir = vim.fn.stdpath("data") .. "/translator"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir .. "/history.txt"
end

local HISTORY = history_path()

---------------------------------------------------------------------
-- UTF-8 安全：按显示宽度截断，避免切断多字节字符产生非法字节
---------------------------------------------------------------------
local function truncate_display(s, max_width)
	if vim.fn.strdisplaywidth(s) <= max_width then
		return s
	end
	local limit = math.max(0, max_width - 3) -- 预留 "..."
	local out = ""
	for _, ch in ipairs(vim.fn.split(s, "\\zs")) do
		if vim.fn.strdisplaywidth(out .. ch) > limit then
			break
		end
		out = out .. ch
	end
	return out .. "..."
end

-- 按显示宽度右侧补空格（中文每字宽 2，不能用字节长度对齐）
local function pad_display(s, width)
	local w = vim.fn.strdisplaywidth(s)
	if w >= width then
		return s
	end
	return s .. string.rep(" ", width - w)
end

local function format_entry(text, trans)
	local left = truncate_display(text, 30)

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

	return pad_display(left, 32) .. " " .. right
end

---------------------------------------------------------------------
-- Persist the translation, de-duplicating against the last 50 entries.
---------------------------------------------------------------------
function M.save(trans)
	if not config.get().history.enable then
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
	-- 显式按 UTF-8 读取，避免文件中偶发的非法字节导致整体回退到 latin1
	vim.bo.fileencoding = "utf-8"
	vim.bo.filetype = "translator_history"
end

-- 导出内部函数供测试
M._format_entry = format_entry
M._truncate_display = truncate_display

return M
