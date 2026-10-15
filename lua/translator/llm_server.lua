-- File: lua/translator/llm_server.lua
-- 本地 LLM 服务（如 llama.cpp / llama-server）的按需启动 + 活跃标记。
--
-- 按需启动：翻译前调用 ensure()，若服务未运行则拉起并异步等待就绪。
-- 空闲回收：每次成功翻译后调用 mark_active() 写入时间戳；外部 watchdog
--           （launchd StartInterval 脚本）依据该时间戳在空闲超时后停止服务，
--           从而释放常驻内存。

local config = require("translator.config")

local async = vim.async

local M = {}

--- 当前是否配置了需要管理的本地 LLM 服务
---@return table|nil
local function server_cfg()
	local s = config.get().llm.server
	if type(s) ~= "table" or type(s.cmd) ~= "table" or #s.cmd == 0 then
		return nil
	end
	return s
end

--- 服务是否已在运行（优先健康检查，回退到进程检测）
---@param s table
---@return boolean
local function running(s)
	local url = s.health
	if url and url ~= "" then
		local out = vim.fn.system({
			"curl", "-s", "--max-time", "2", "-o", "/dev/null", "-w", "%{http_code}", url,
		})
		return vim.trim(out) == "200"
	end
	-- 未配置 health 时按进程名判断
	local name = s.cmd[1] or ""
	if name == "" then
		return false
	end
	return vim.fn.system({ "pgrep", "-f", name }):match("%d+") ~= nil
end

--- 记录一次活跃（供外部 watchdog 判断空闲并回收）
function M.mark_active()
	local s = server_cfg()
	if not s then
		return
	end
	local stamp = s.stamp or (vim.fn.stdpath("cache") .. "/translator/llm.last_active")
	local dir = vim.fn.fnamemodify(stamp, ":h")
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	local f = io.open(stamp, "w")
	if f then
		f:write(tostring(os.time()))
		f:close()
	end
end

--- 按需启动本地服务并等待就绪（异步，不阻塞主循环）。
--- 未配置 llm.server 或已运行时立即返回。
function M.ensure()
	local s = server_cfg()
	if not s then
		return
	end
	if running(s) then
		return
	end

	-- 拉起服务（detach：Neovim 退出后服务仍独立运行，交给 watchdog 回收）
	vim.fn.jobstart(s.cmd, { detach = true })
	M.mark_active()

	local wait = tonumber(s.wait) or 120
	local step = tonumber(s.poll_ms) or 1000
	local elapsed = 0
	while elapsed < wait do
		async.sleep(step)
		elapsed = elapsed + step / 1000
		if running(s) then
			return
		end
	end
end

return M
