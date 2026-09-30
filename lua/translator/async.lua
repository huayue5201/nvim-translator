-- File: lua/translator/async.lua
-- vim.async 便捷封装（本插件只用到「延后一轮」与「延迟一次」两种模式）。

local M = {}

local async = vim.async

--- 观测任务失败：忽略取消，其余错误显式报出（顶层任务默认静默）。
--- on_complete 可能在快速上下文中触发，必须切回主循环再调 UI API。
---@param task vim.async.Task
---@return vim.async.Task
local function observe(task)
	task:on_complete(function(err)
		if err == nil or tostring(err):find("closed", 1, true) then
			return
		end
		local message = tostring(err)
		vim.schedule(function()
			vim.notify("[translator] async: " .. message, vim.log.levels.ERROR)
		end)
	end)
	return task
end

--- 延后到下一轮事件循环执行（等价 vim.schedule）。
---@param fn fun()
---@return vim.async.Task
function M.defer(fn)
	return observe(async.run(function()
		async.sleep(0)
		fn()
	end))
end

--- 延迟 delay 毫秒后执行一次。
---@param delay integer
---@param fn fun()
---@return vim.async.Task
function M.delay(delay, fn)
	return observe(async.run(function()
		async.sleep(delay)
		fn()
	end))
end

return M
