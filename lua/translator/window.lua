-- File: lua/translator/window.lua
-- Neovim-native window dispatcher for translator.nvim
-- 保留原版全部功能 + 宽松模式自动适配内容

local M = {}

---------------------------------------------------------------------
-- Detect window type
---------------------------------------------------------------------
local function get_wintype()
	local t = vim.g.translator_window_type or "float"
	if t == "preview" then
		return "preview"
	end
	return "float"
end

---------------------------------------------------------------------
-- Compute content size (宽松模式自动适配)
---------------------------------------------------------------------
local function compute_size(lines)
	-------------------------------------------------------------------
	-- 1. 计算内容宽度与高度
	-------------------------------------------------------------------
	local content_width = 0
	for _, line in ipairs(lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end
	local content_height = #lines

	-------------------------------------------------------------------
	-- 2. 宽松模式 padding（视觉更美观）
	-------------------------------------------------------------------
	local padding_w = 6 -- 左右留白
	local padding_h = 2 -- 上下留白

	-------------------------------------------------------------------
	-- 3. 最小尺寸（避免窗口太小）
	-------------------------------------------------------------------
	local min_w = 20
	local min_h = 3

	-------------------------------------------------------------------
	-- 4. 最大尺寸（来自用户配置）
	-------------------------------------------------------------------
	local max_w = vim.g.translator_window_max_width or 0.4
	if max_w < 1 then
		max_w = math.floor(max_w * vim.o.columns)
	end

	local max_h = vim.g.translator_window_max_height or 0.3
	if max_h < 1 then
		max_h = math.floor(max_h * vim.o.lines)
	end

	-------------------------------------------------------------------
	-- 5. 计算最终宽度（内容 + padding → 限制在 min/max 之间）
	-------------------------------------------------------------------
	local width = content_width + padding_w
	width = math.max(width, min_w)
	width = math.min(width, max_w)

	-------------------------------------------------------------------
	-- 6. 计算最终高度（内容 + padding → 限制在 min/max 之间）
	-------------------------------------------------------------------
	local height = content_height + padding_h
	height = math.max(height, min_h)
	height = math.min(height, max_h)

	return width, height
end

---------------------------------------------------------------------
-- Smart positioning (auto up/down)
---------------------------------------------------------------------
local function compute_position(height)
	local cursor_row = vim.fn.winline()
	local win_top = cursor_row
	local win_bottom = vim.o.lines - cursor_row

	local show_above = win_bottom < height + 3

	if show_above then
		return -height - 2 -- show above cursor
	else
		return 1 -- show below cursor
	end
end

---------------------------------------------------------------------
-- Main entry
---------------------------------------------------------------------
function M.open(lines)
	local width, height = compute_size(lines)

	local cfg = {
		width = width,
		height = height,
		row = compute_position(height),
		col = 0,
	}

	local type = get_wintype()
	if type == "float" then
		require("translator.window.float").create(lines, cfg)
	else
		require("translator.window.preview").create(lines, cfg)
	end
end

return M
