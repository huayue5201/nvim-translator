-- File: lua/translator/cancel.lua
-- Shared cancel key for in-flight requests.
--
-- Every component that starts asynchronous work (a window translation, a
-- buffer-wide virtual-text batch, ...) registers a handler. While at least one
-- handler is registered the configured key (default <Esc>) aborts all of them;
-- afterwards the user's own mapping, if any, is restored.

local config = require("translator.config")

local M = {}

local handlers = {}
local saved = nil -- mode -> previous global mapping dictionary

local function key()
	local k = config.get().cancel_key
	if k == nil then
		return "<Esc>"
	end
	return k
end

local function install()
	local k = key()
	if k == false or k == "" then
		return
	end
	saved = {}
	for _, mode in ipairs({ "n", "v" }) do
		saved[mode] = vim.fn.maparg(k, mode, false, true)
		vim.keymap.set(mode, k, M.cancel, { silent = true, nowait = true, desc = "Cancel translation" })
	end
end

local function uninstall()
	if not saved then
		return
	end
	local k = key()
	local prev = saved
	saved = nil
	for _, mode in ipairs({ "n", "v" }) do
		pcall(vim.keymap.del, mode, k)
		if prev[mode] and prev[mode].lhs then
			pcall(vim.fn.mapset, mode, false, prev[mode])
		end
	end
end

--- Abort everything in flight (the cancel key handler).
function M.cancel()
	local pending = handlers
	handlers = {}
	uninstall()
	for _, handler in ipairs(pending) do
		pcall(handler)
	end
end

--- Register a cancel handler.
---@param handler fun()
function M.register(handler)
	if vim.tbl_contains(handlers, handler) then
		return
	end
	handlers[#handlers + 1] = handler
	if #handlers == 1 then
		install()
	end
end

--- Drop a handler; the cancel key is removed with the last one.
---@param handler fun()
function M.unregister(handler)
	for i, h in ipairs(handlers) do
		if h == handler then
			table.remove(handlers, i)
			break
		end
	end
	if #handlers == 0 then
		uninstall()
	end
end

return M
