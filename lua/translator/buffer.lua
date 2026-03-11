-- File: lua/translator/buffer.lua
-- Neovim-native buffer utilities for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Create scratch buffer
---------------------------------------------------------------------
function M.create_scratch_buf(lines)
	local bufnr = vim.api.nvim_create_buf(false, true)

	vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

	if lines and type(lines) == "table" then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	return bufnr
end

---------------------------------------------------------------------
-- Initialize buffer for translator window
---------------------------------------------------------------------
function M.init(bufnr)
	vim.api.nvim_buf_set_option(bufnr, "filetype", "translator")
	vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
end

return M
