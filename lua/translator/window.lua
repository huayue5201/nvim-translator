-- File: lua/translator/window.lua

local M = {}

local function get_wintype()
	local t = vim.g.translator_window_type or "float"
	if t == "preview" then
		return "preview"
	end
	return "float"
end

local function compute_size(lines)
	local content_width = 0
	for _, line in ipairs(lines) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end

	local content_height = #lines

	local padding_w = 6
	local padding_h = 2

	local min_w = 20
	local min_h = 3

	local max_w = vim.g.translator_window_max_width or 0.4
	if max_w < 1 then
		max_w = math.floor(max_w * vim.o.columns)
	end

	local max_h = vim.g.translator_window_max_height or 0.3
	if max_h < 1 then
		max_h = math.floor(max_h * vim.o.lines)
	end

	local width = content_width + padding_w
	width = math.max(width, min_w)
	width = math.min(width, max_w)

	local height = content_height + padding_h
	height = math.max(height, min_h)
	height = math.min(height, max_h)

	return width, height
end

---------------------------------------------------------------------
-- FIXED: split window support
---------------------------------------------------------------------
local function compute_position(height)
	local win_height = vim.api.nvim_win_get_height(0)
	local cursor_row = vim.fn.winline()

	local win_bottom = win_height - cursor_row

	local show_above = win_bottom < height + 3

	if show_above then
		return -height - 2
	else
		return 1
	end
end

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
