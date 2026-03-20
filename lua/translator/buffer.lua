-- File: lua/translator/buffer.lua
-- Neovim-native buffer utilities for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Create scratch buffer
---------------------------------------------------------------------
function M.create_scratch_buf(lines)
	local bufnr = vim.api.nvim_create_buf(false, true)

	local opts = {
		buftype = "nofile",
		bufhidden = "wipe",
		swapfile = false,
		modifiable = true,
	}

	for opt, value in pairs(opts) do
		vim.api.nvim_set_option_value(opt, value, { buf = bufnr })
	end

	if lines and type(lines) == "table" then
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	end

	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
	return bufnr
end

---------------------------------------------------------------------
-- Initialize buffer for translator window
---------------------------------------------------------------------
function M.init(bufnr)
	local opts = {
		filetype = "translator",
		buftype = "nofile",
		bufhidden = "wipe",
		swapfile = false,
		modifiable = false,
	}

	for opt, value in pairs(opts) do
		vim.api.nvim_set_option_value(opt, value, { buf = bufnr })
	end
end

return M
