-- Shared helpers for user-level scenario tests (loaded via `luafile`).
--
-- The suite drives the plugin exactly like a user would (commands, real
-- <Esc> key presses through the mapping layer) against `fake_backend.py`,
-- a deliberately slow backend so that requests can be cancelled mid-flight.
-- See test/user/README.md.

local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h")
local root = vim.fn.fnamemodify(here .. "/../..", ":p")
local bin = root .. "test/user/fake_backend.py"

vim.opt.rtp:prepend(root:gsub("/$", ""))

H = { msgs = {} }
vim.notify = function(msg, level)
	table.insert(H.msgs, tostring(level) .. ": " .. tostring(msg))
end

-- The plugin reports through nvim_echo; record that too.
local echo = vim.api.nvim_echo
vim.api.nvim_echo = function(chunks, history, opts)
	local parts = {}
	for _, chunk in ipairs(chunks or {}) do
		parts[#parts + 1] = tostring(chunk[1])
	end
	table.insert(H.msgs, table.concat(parts))
	return echo(chunks, history, opts)
end

--- Point the plugin at the fake backend and give the buffer some text.
---@param over table|nil extra `setup()` overrides
function H.setup(over)
	require("translator").setup(vim.tbl_deep_extend("force", {
		cache = { enable = false },
		debug = true,
	}, over or {}))
	require("translator.binary").get = function()
		return bin
	end
	vim.cmd("runtime! plugin/translator.lua")
	vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

--- Number of floating windows (spinner + result window).
function H.floats()
	local n = 0
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_config(win).relative ~= "" then
			n = n + 1
		end
	end
	return n
end

--- Number of live fake backend processes.
function H.procs()
	local out = vim.fn.system({ "pgrep", "-f", bin })
	return #vim.split(vim.trim(out), "\n", { trimempty = true })
end

--- Press <Esc> the way a user does (goes through mappings; "x" flag would
--- bypass them, so the "x" flag is used *without* "n").
function H.esc()
	vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)
end

function H.wait(ms)
	vim.wait(ms, function()
		return false
	end)
end

--- lhs currently mapped in normal mode ("" when unmapped).
function H.map()
	return vim.fn.maparg("<Esc>", "n")
end

--- Assert a group of checks and print one PASS/FAIL line.
---@param name string
---@param checks table[] { label, ok, actual }
function H.report(name, checks)
	local ok = true
	local parts = {}
	for _, c in ipairs(checks) do
		ok = ok and c[2] and true
		parts[#parts + 1] = (c[2] and "ok:" or "FAIL:") .. c[1] .. (c[2] and "" or ("=" .. vim.inspect(c[3])))
	end
	print((ok and "PASS " or "FAIL ") .. name .. " | " .. table.concat(parts, " "))
end

return H
