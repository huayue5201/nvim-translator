-- File: lua/translator/logger.lua

local M = {}

local LOG = {}

local LOG_FILE = vim.fn.stdpath("data") .. "/translator/log.txt"

local function write_file(line)
	if not vim.g.translator_debug then
		return
	end

	local f = io.open(LOG_FILE, "a")

	if f then
		f:write(line .. "\n")
		f:close()
	end
end

function M.log(info)
	local trace = debug.getinfo(2, "Sl")
	local src = (trace.short_src or "unknown") .. ":" .. (trace.currentline or 0)

	local entry = {
		trace = src,
		info = info,
	}

	table.insert(LOG, entry)

	write_file(src .. " -> " .. vim.inspect(info))
end

function M.init()
	LOG = {}
end

function M.open_log()
	vim.cmd("tabnew")

	local bufnr = vim.api.nvim_get_current_buf()

	vim.bo[bufnr].buftype = "nofile"
	vim.bo[bufnr].bufhidden = "wipe"
	vim.bo[bufnr].swapfile = false
	vim.bo[bufnr].modifiable = true

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

	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

	vim.bo[bufnr].modifiable = false

	vim.cmd("normal! gg")
end

return M
