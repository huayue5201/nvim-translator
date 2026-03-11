-- FileName: float.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Floating window module for translator plugin (thanks coc.nvim)

local buffer = require("translator.buffer")
local util = require("translator.util")

local M = {}

-- 模块级变量，存储窗口ID
local winid = -1
local bd_winid = -1

-- max firstline of lines, height > 0, width > 0
local function max_firstline(lines, height, width)
	local max = #lines
	local remain = height
	for i = #lines, 1, -1 do
		local line = lines[i]
		local w = math.max(1, vim.fn.strdisplaywidth(line))
		local dh = math.ceil(tonumber(w) / width)
		if remain - dh < 0 then
			break
		end
		remain = remain - dh
		max = max - 1
	end
	return math.min(#lines, max + 1)
end

local function content_height(bufnr, width, wrap)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		return 0
	end
	if not wrap then
		return vim.api.nvim_buf_line_count(bufnr)
	end
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local total = 0
	for _, line in ipairs(lines) do
		local dw = math.max(1, vim.fn.strdisplaywidth(line))
		total = total + math.ceil(tonumber(dw) / width)
	end
	return total
end

-- Get best lnum by topline
local function get_cursorline(topline, lines, scrolloff, width, height)
	local lastline = #lines
	if topline == lastline then
		return lastline
	end
	local bottomline = topline
	local used = 0
	for lnum = topline, lastline do
		local w = math.max(1, vim.fn.strdisplaywidth(lines[lnum]))
		local dh = math.ceil(tonumber(w) / width)
		if used + dh >= height or lnum == lastline then
			bottomline = lnum
			break
		end
		used = used + dh
	end
	local cursorline = topline + scrolloff
	if cursorline + scrolloff > bottomline then
		-- unable to satisfy scrolloff
		cursorline = math.floor((topline + bottomline) / 2)
	end
	return cursorline
end

-- Get firstline for full scroll
local function get_topline(topline, lines, forward, height, width)
	local used = 0
	local lnums = {}
	if forward then
		for i = topline, #lines do
			table.insert(lnums, i)
		end
	else
		for i = topline, 1, -1 do
			table.insert(lnums, i)
		end
	end

	local result_topline = forward and #lines or 1
	for _, lnum in ipairs(lnums) do
		local w = math.max(1, vim.fn.strdisplaywidth(lines[lnum]))
		local dh = math.ceil(tonumber(w) / width)
		if used + dh >= height then
			result_topline = lnum
			break
		end
		used = used + dh
	end

	if result_topline == topline then
		if forward then
			result_topline = math.min(#lines, topline + 1)
		else
			result_topline = math.max(1, topline - 1)
		end
	end
	return result_topline
end

-- topline content_height content_width
local function get_options(win_id)
	local width = vim.api.nvim_win_get_width(win_id)
	-- 检查 foldcolumn
	local foldcolumn = vim.fn.getwinvar(win_id, "&foldcolumn", 0)
	if foldcolumn and foldcolumn > 0 then
		width = width - 1
	end

	local wininfo = vim.fn.getwininfo(win_id)[1]
	return {
		topline = wininfo.topline,
		height = vim.api.nvim_win_get_height(win_id),
		width = width,
	}
end

local function win_execute(win_id, command)
	local current = vim.api.nvim_get_current_win()
	pcall(vim.api.nvim_set_current_win, win_id)
	vim.cmd(command)
	pcall(vim.api.nvim_set_current_win, current)
end

local function win_setview(win_id, topline, lnum)
	local cmd = string.format('call winrestview({"lnum":%d,"topline":%d})', lnum, topline)
	win_execute(win_id, cmd)
end

local function win_exists(win_id)
	return vim.fn.getwininfo(win_id) and #vim.fn.getwininfo(win_id) > 0
end

local function win_close_float()
	if vim.api.nvim_get_current_win() == winid then
		return
	else
		if win_exists(winid) then
			pcall(vim.api.nvim_win_close, winid, true)
		end
		if win_exists(bd_winid) then
			pcall(vim.api.nvim_win_close, bd_winid, true)
		end
		-- 清除自动命令
		pcall(vim.api.nvim_del_augroup_by_name, "close_translator_window")
	end
end

function M.has_scroll()
	return win_exists(winid)
end

function M.scroll(forward, amount)
	amount = amount or 0
	if not win_exists(winid) then
		util.show_msg("No translator windows")
	else
		M.scroll_win(winid, forward, amount)
	end
	return vim.fn.mode():match("^i") or vim.fn.mode() == "v" and "" or "<Ignore>"
end

function M.scroll_win(win_id, forward, amount)
	local opts = get_options(win_id)
	local lines = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win_id), 0, -1, false)
	local maxfirst = max_firstline(lines, opts.height, opts.width)
	local topline = opts.topline
	local height = opts.height
	local width = opts.width
	local scrolloff = vim.fn.getwinvar(win_id, "&scrolloff", 0)

	if forward and topline >= maxfirst then
		return
	end
	if not forward and topline == 1 then
		return
	end

	if amount == 0 then
		topline = get_topline(opts.topline, lines, forward, height, width)
	else
		topline = topline + (forward and amount or -amount)
	end

	topline = forward and math.min(maxfirst, topline) or math.max(1, topline)
	local lnum = get_cursorline(topline, lines, scrolloff, width, height)
	win_setview(win_id, topline, lnum)

	local top = get_options(win_id).topline
	-- not changed
	if top == opts.topline then
		if forward then
			win_setview(win_id, topline + 1, lnum + 1)
		else
			win_setview(win_id, topline - 1, lnum - 1)
		end
	end
end

function M.create(linelist, configs)
	-- 关闭已存在的浮动窗口
	win_close_float()

	-- 创建主内容窗口
	local content_opts = {
		relative = "editor",
		anchor = configs.anchor,
		row = configs.row + (configs.anchor:sub(1, 1) == "N" and 1 or -1),
		col = configs.col + (configs.anchor:sub(2, 2) == "W" and 1 or -1),
		width = configs.width - 2,
		height = configs.height - 2,
		style = "minimal",
		zindex = 32000,
	}

	-- 创建内容缓冲区
	local bufnr = buffer.create_scratch_buf(linelist)
	buffer.init(bufnr)

	-- 创建内容窗口
	local content_winid = vim.api.nvim_open_win(bufnr, false, content_opts)
	-- 初始化窗口（需要实现 window.lua）
	-- require('translator.window').init(content_winid)

	-- 创建边框窗口
	local border_opts = {
		relative = "editor",
		anchor = configs.anchor,
		row = configs.row,
		col = configs.col,
		width = configs.width,
		height = configs.height,
		focusable = false,
		style = "minimal",
		zindex = 32000,
	}

	-- 创建边框缓冲区
	local border_bufnr = buffer.create_border(configs)
	local border_winid = vim.api.nvim_open_win(border_bufnr, false, border_opts)
	vim.api.nvim_win_set_option(border_winid, "winhl", "Normal:TranslatorBorder")

	-- 切换到内容窗口但不改变焦点
	vim.cmd("noautocmd call win_gotoid(" .. content_winid .. ")")
	vim.cmd("noautocmd wincmd p")

	-- 设置自动命令组
	local augroup = vim.api.nvim_create_augroup("close_translator_window", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
		group = augroup,
		buffer = bufnr,
		callback = function()
			vim.defer_fn(win_close_float, 100)
		end,
	})

	winid = content_winid
	bd_winid = border_winid

	return { content_winid, border_winid }
end

return M
