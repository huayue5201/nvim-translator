-- File: lua/translator/proc.lua
-- Thin async wrapper around vim.system.
--
-- vim.system runs its callbacks in a fast (libuv) context, where UI and
-- async-runtime calls are not allowed; every callback is therefore handed
-- back to the main loop with vim.schedule().

local async = vim.async

local M = {}

--- Key for a streaming output callback. Neovim 0.13 renamed the
--- `on_stdout`/`on_stderr` options to `stdout`/`stderr`.
M.STDOUT_KEY = vim.fn.has("nvim-0.13") == 1 and "stdout" or "on_stdout"

local function normalize(res)
	return {
		code = res.code,
		stdout = res.stdout or "",
		stderr = res.stderr or "",
	}
end

--- Run a command to completion and await its result.
---@param cmd string[]
---@param opts table|nil extra vim.system options (env, stdin, text, ...)
---@return { code:integer, stdout:string, stderr:string }
function M.run(cmd, opts)
	local options = vim.tbl_extend("force", { text = true }, opts or {})

	return async.await(function(done)
		local system = vim.system(cmd, options, function(res)
			vim.schedule(function()
				done(normalize(res))
			end)
		end)

		return {
			close = function(_, callback)
				pcall(system.kill, system, 15)
				if callback then
					callback()
				end
			end,
		}
	end)
end

--- Fire-and-forget spawn; `on_exit` (optional) runs on the main loop.
---@param cmd string[]
---@param opts table|nil
---@param on_exit fun(result:{code:integer, stdout:string, stderr:string})|nil
---@return vim.SystemObj
function M.spawn(cmd, opts, on_exit)
	local options = vim.tbl_extend("force", { text = true }, opts or {})
	return vim.system(cmd, options, function(res)
		if on_exit then
			local result = normalize(res)
			vim.schedule(function()
				on_exit(result)
			end)
		end
	end)
end

return M
