-- File: lua/translator/logger.lua
-- Neovim-native logger for translator.nvim

local M = {}

-- In-memory log
local LOG = {}

---------------------------------------------------------------------
-- Append log entry
---------------------------------------------------------------------
function M.log(info)
	local trace = debug.getinfo(2, "Sl")
	local src = (trace.short_src or "unknown") .. ":" .. (trace.currentline or 0)

	table.insert(LOG, {
		trace = src,
		info = info,
	})
end

---------------------------------------------------------------------
-- Clear log
---------------------------------------------------------------------
function M.init()
	LOG = {}
end

---------------------------------------------------------------------
-- Open log window
---------------------------------------------------------------------
function M.open_log()
	-- Create new tab
	vim.cmd("tabnew")
	local bufnr = vim.api.nvim_get_current_buf()

	-- Buffer options
	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true
	vim.bo[bufnr].filetype = "translator_log"

	-- Build lines
	local lines = {}

	for _, entry in ipairs(LOG) do
		table.insert(lines, "@" .. entry.trace)

		if type(entry.info) == "table" then
			local s = vim.inspect(entry.info)
			for line in s:gmatch("[^\n]+") do
				table.insert(lines, line)
			end
		else
			table.insert(lines, tostring(entry.info))
		end

		table.insert(lines, "")
	end

	-- Write lines
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
	vim.bo[bufnr].modifiable = false

	-- Highlight
	vim.cmd([[
    syn match TranslatorLogTrace /^@.*$/
    syn match TranslatorLogInfo /^[^@].*$/

    hi def link TranslatorLogTrace Keyword
    hi def link TranslatorLogInfo String
  ]])

	vim.cmd("normal! gg")
end

return M
