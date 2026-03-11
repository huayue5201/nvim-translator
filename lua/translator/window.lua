-- FileName: window.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Window module for translator plugin

local util = require("translator.util")

local M = {}

-- 检测支持的窗口类型
local has_float = vim.fn.has("nvim") == 1 and vim.fn.exists("*nvim_win_set_config") == 1
-- 注意：popup 是 Vim 的特性，在 Neovim 中我们用 float 模拟
local has_popup = false -- 在 Neovim 中不支持 Vim 的 popup

-- 获取要使用的窗口类型
local function win_gettype()
	local window_type = vim.g.translator_window_type or "popup"

	if window_type == "popup" then
		if has_float then
			return "float"
		elseif has_popup then
			return "popup"
		else
			util.show_msg("popup is not supported, use preview window", "warning")
			return "preview"
		end
	end
	return "preview"
end

local wintype = win_gettype()

-- 计算窗口大小
local function win_getsize(translation, max_width, max_height)
	local width = 0
	local height = 0

	for _, line in ipairs(translation) do
		local line_width = vim.fn.strdisplaywidth(line)
		if line_width > max_width then
			width = max_width
			height = height + math.floor(line_width / max_width) + 1
		else
			width = math.max(line_width, width)
			height = height + 1
		end
	end

	if height > max_height then
		height = max_height
	end
	return { width, height }
end

-- 计算窗口位置
local function win_getoptions(width, height)
	-- 获取当前窗口在屏幕上的位置
	local pos = vim.fn.win_screenpos(0)
	local y_pos = pos[1] + vim.fn.winline() - 1
	local x_pos = pos[2] + vim.fn.wincol() - 1

	local border = vim.tbl_isempty(vim.g.translator_window_borderchars or {}) and 0 or 2
	local y_margin = 2
	local final_width = width
	local final_height = height

	-- 计算垂直方向
	local vert, y_offset
	if y_pos + height + border + y_margin <= vim.o.lines then
		vert = "N"
		y_offset = 0
	elseif y_pos - height - border - y_margin >= 0 then
		vert = "S"
		y_offset = -1
	elseif vim.o.lines - y_pos >= y_pos then
		vert = "N"
		y_offset = 0
		final_height = vim.o.lines - y_pos - border - y_margin
	else
		vert = "S"
		y_offset = -1
		final_height = y_pos - border - y_margin
	end

	-- 计算水平方向
	local hor, x_offset
	if x_pos + width + border <= vim.o.columns then
		hor = "W"
		x_offset = -1
	elseif x_pos - width - border >= 0 then
		hor = "E"
		x_offset = 0
	elseif vim.o.columns - x_pos >= x_pos then
		hor = "W"
		x_offset = -1
		final_width = vim.o.columns - x_pos - border
	else
		hor = "E"
		x_offset = 0
		final_width = x_pos - border
	end

	local anchor = vert .. hor
	local row = y_pos + y_offset
	local col = x_pos + x_offset

	return { anchor, row, col, final_width, final_height }
end

-- 初始化窗口
function M.init(winid)
	-- 设置窗口选项
	-- FIX:ref:74f1fc
	vim.api.nvim_win_set_option(winid, "wrap", true)
	vim.api.nvim_win_set_option(winid, "conceallevel", 3)
	vim.api.nvim_win_set_option(winid, "number", false)
	vim.api.nvim_win_set_option(winid, "relativenumber", false)
	vim.api.nvim_win_set_option(winid, "spell", false)
	vim.api.nvim_win_set_option(winid, "foldcolumn", 0)

	-- 设置窗口颜色
	if vim.fn.has("nvim") == 1 then
		vim.api.nvim_win_set_option(winid, "winhl", "Normal:Translator")
	else
		-- Vim 的 wincolor（但在 Neovim 中可能不支持）
		vim.api.nvim_win_set_option(winid, "wincolor", "Translator")
	end
end

-- 打开翻译窗口
function M.open(content)
	-- 计算最大宽度
	local max_width = vim.g.translator_window_max_width or 0.4
	if type(max_width) == "number" and max_width < 1 then
		max_width = max_width * vim.o.columns
	end
	max_width = math.floor(max_width)

	-- 计算最大高度
	local max_height = vim.g.translator_window_max_height or 0.3
	if type(max_height) == "number" and max_height < 1 then
		max_height = max_height * vim.o.lines
	end
	max_height = math.floor(max_height)

	-- 获取窗口大小和位置
	local size = win_getsize(content, max_width, max_height)
	local width = size[1]
	local height = size[2]

	local opts = win_getoptions(width, height)
	local anchor = opts[1]
	local row = opts[2]
	local col = opts[3]
	local final_width = opts[4]
	local final_height = opts[5]

	-- 调整内容以适应窗口宽度
	local linelist = util.fit_lines(content, final_width)

	local configs = {
		anchor = anchor,
		row = row,
		col = col,
		width = final_width + 2,
		height = final_height + 2,
		title = "",
		borderchars = vim.g.translator_window_borderchars or { "─", "│", "─", "│", "┌", "┐", "┘", "└" },
	}

	-- 根据窗口类型创建窗口
	if wintype == "float" then
		require("translator.window.float").create(linelist, configs)
	elseif wintype == "popup" then
		require("translator.window.popup").create(linelist, configs)
	else -- preview
		require("translator.window.preview").create(linelist, configs)
	end
end

return M
