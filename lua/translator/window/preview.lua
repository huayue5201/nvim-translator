-- File: lua/translator/window/preview.lua
-- Neovim-native preview window for translator.nvim

local buffer = require("translator.buffer")
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
	pcall(vim.api.nvim_del_augroup_by_name, "translator_preview_close")
end

function M.create(lines, cfg)
	close()

	local bufnr = buffer.create_scratch_buf(lines)
	buffer.init(bufnr)

	-------------------------------------------------------------------
	-- Preview window (single border, fixed position)
	-------------------------------------------------------------------
	state.win = vim.api.nvim_open_win(bufnr, false, {
		relative = "editor",
		row = cfg.row,
		col = cfg.col,
		width = cfg.width,
		height = cfg.height,
		style = "minimal",
		border = "rounded",
		focusable = false,
		zindex = 40,
	})

	vim.api.nvim_win_set_option(state.win, "winhl", "Normal:TranslatorPreview")

	-------------------------------------------------------------------
	-- Auto-close (same as float.lua)
	-------------------------------------------------------------------
	local aug = vim.api.nvim_create_augroup("translator_preview_close", { clear = true })
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
