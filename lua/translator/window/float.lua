-- File: lua/translator/window/float.lua
-- Cursor-following double-border floating window

local buffer = require("translator.buffer")
local util = require("translator.util") -- ★ 新增：用于 fit_lines()
local M = {}

local state = {
	outer = nil,
	inner = nil,
}

local function win_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function close()
	if win_valid(state.inner) then
		pcall(vim.api.nvim_win_close, state.inner, true)
	end
	if win_valid(state.outer) then
		pcall(vim.api.nvim_win_close, state.outer, true)
	end
	state.inner = nil
	state.outer = nil
	pcall(vim.api.nvim_del_augroup_by_name, "translator_float_close")
end

function M.has_scroll()
	return win_valid(state.inner)
end

function M.scroll(forward, amount)
	if not M.has_scroll() then
		return "<Ignore>"
	end
	amount = amount or 1
	vim.api.nvim_win_call(state.inner, function()
		local key = forward and "<C-e>" or "<C-y>"
		for _ = 1, amount do
			vim.cmd("normal! " .. key)
		end
	end)
	return "<Ignore>"
end

function M.create(lines, cfg)
	close()

	-------------------------------------------------------------------
	-- ★ 在写入 buffer 之前对内容进行居中排版
	-- 使用内层窗口宽度（cfg.width - 2）
	-------------------------------------------------------------------
	lines = util.fit_lines(lines, cfg.width - 2)

	-------------------------------------------------------------------
	-- 创建 buffer（内容已经经过居中处理）
	-------------------------------------------------------------------
	local bufnr = buffer.create_scratch_buf(lines)
	buffer.init(bufnr)

	-------------------------------------------------------------------
	-- 外层窗口（double border）
	-------------------------------------------------------------------
	state.outer = vim.api.nvim_open_win(bufnr, false, {
		relative = "cursor",
		row = 1, -- 光标下方一行
		col = 0,
		width = cfg.width,
		height = cfg.height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 50,
	})
	vim.api.nvim_win_set_option(state.outer, "winhl", "Normal:TranslatorBorder")

	-------------------------------------------------------------------
	-- 内层窗口（rounded border）
	-------------------------------------------------------------------
	state.inner = vim.api.nvim_open_win(bufnr, false, {
		relative = "cursor",
		row = 2, -- 比外层向内偏移 1 行
		col = 1, -- 比外层向内偏移 1 列
		width = cfg.width - 2,
		height = cfg.height - 2,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 60,
	})
	vim.api.nvim_win_set_option(state.inner, "winhl", "Normal:Translator")

	-------------------------------------------------------------------
	-- 自动关闭（严格 coc.nvim 风格）
	-------------------------------------------------------------------
	local aug = vim.api.nvim_create_augroup("translator_float_close", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = aug,
		buffer = 0,
		callback = function()
			vim.defer_fn(close, 10)
		end,
	})

	return state.inner, state.outer
end

M.close = close
return M
