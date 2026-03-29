-- File: lua/translator/window/float.lua
-- Cursor-following floating window with double border

local buffer = require("translator.buffer")
local util = require("translator.util")
local M = {}

local state = {
	win = nil,
}

local function win_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function close()
	if win_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	pcall(vim.api.nvim_del_augroup_by_name, "translator_float_close")
end

function M.has_scroll()
	return win_valid(state.win)
end

function M.scroll(forward, amount)
	if not M.has_scroll() then
		return "<Ignore>"
	end
	amount = amount or 1
	vim.api.nvim_win_call(state.win, function()
		local key = forward and "<C-e>" or "<C-y>"
		for _ = 1, amount do
			vim.cmd("normal! " .. key)
		end
	end)
	return "<Ignore>"
end

function M.create(lines, cfg)
	close()

	-- 对内容进行居中排版
	lines = util.fit_lines(lines, cfg.width)

	-- 创建 buffer
	local bufnr = buffer.create_scratch_buf(lines)
	buffer.init(bufnr)

	-- 单层浮窗，使用 double border
	state.win = vim.api.nvim_open_win(bufnr, false, {
		relative = "cursor",
		row = 1,
		col = 0,
		width = cfg.width,
		height = cfg.height,
		style = "minimal",
		border = "rounded", -- 直接使用双边框
		focusable = false,
		zindex = 50,
	})
	vim.api.nvim_win_set_option(state.win, "winhl", "Normal:Translator")

	-- 自动关闭
	local aug = vim.api.nvim_create_augroup("translator_float_close", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = aug,
		buffer = 0,
		callback = function()
			vim.defer_fn(close, 10)
		end,
	})

	return state.win
end

M.close = close
return M
