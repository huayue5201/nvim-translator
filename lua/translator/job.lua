-- File: lua/translator/job.lua

local logger = require("translator.logger")
local action = require("translator.action")
local history = require("translator.history")
local util = require("translator.util")
local state = require("translator.state")
local cache = require("translator.cache")
local config = require("translator.config")
local spinner = require("translator.spinner")

local async = vim.async

local M = {}

-- 最近一次成功翻译的结果（仅用于 echo 模式下报错时的回显）
local stdout_save = nil

-- 在途翻译任务：新请求会取消它（中止子进程 + 回收 spinner）
local translate_task = nil

---------------------------------------------------------------------
-- Apply a (fresh or cached) translation result: state + display + history.
---------------------------------------------------------------------
function M.apply_result(displaymode, translations, options)
	stdout_save = translations
	state.set(translations, options)

	if displaymode == "echo" then
		action.echo(translations)
	elseif displaymode == "window" then
		action.window(translations, options)
	elseif displaymode == "interactive" then
		action.interactive(translations, options)
	else
		action.replace(translations)
	end

	history.save(translations)
end

---------------------------------------------------------------------
-- Run one backend request; returns (stdout[], stderr[]) when the job exits.
--
-- The await callback returns a closable handle so that cancelling the
-- surrounding task aborts the child process instead of leaking it.
---------------------------------------------------------------------
local function spawn(cmd, env)
	return async.await(function(done)
		local stdout, stderr = {}, {}

		local opts = {
			stdout_buffered = true,
			stderr_buffered = true,
			on_stdout = function(_, data)
				stdout = data or {}
			end,
			on_stderr = function(_, data)
				stderr = data or {}
			end,
			on_exit = function()
				-- on_exit 是 luv（快速事件）回调；必须切回主循环再唤醒任务，
				-- 否则 await 之下的 UI 调用会报 E5560 fast event context。
				-- 顺带给缓冲的 on_stdout/on_stderr 一个先送达的机会。
				local out, err = stdout, stderr
				vim.schedule(function()
					done(out, err)
				end)
			end,
		}
		if env then
			opts.env = env
		end

		local id = vim.fn.jobstart(cmd, opts)
		if id <= 0 then
			done({}, { "failed to start translation backend" })
			return nil
		end

		return {
			close = function(_, callback)
				pcall(vim.fn.jobstop, id)
				if callback then
					callback()
				end
			end,
		}
	end)
end

---------------------------------------------------------------------
-- Result handling
---------------------------------------------------------------------
local function handle_stdout(displaymode, options, key, message)
	logger.log(message)

	local ok, translations = pcall(vim.json.decode, message)
	if not ok or not translations then
		util.show_msg("Translation failed", "error")
		return
	end

	-- 先写缓存，这样重复请求可以完全跳过后端。
	cache.set(key, translations)
	M.apply_result(displaymode, translations, options)
end

local function handle_stderr(displaymode, message)
	logger.log(message)
	util.show_msg(message, "error")

	if stdout_save and displaymode == "echo" then
		action.echo(stdout_save)
	end
end

---------------------------------------------------------------------
-- Start one translation, cancelling any request already in flight.
---------------------------------------------------------------------
function M.jobstart(cmd, displaymode, env, options, key)
	if translate_task then
		translate_task:close()
	end

	vim.g.translator_status = "translating"

	-- 请求延时期间在光标处显示旋转提示（可用 config.spinner.enable 关闭）。
	if config.get().spinner.enable ~= false then
		spinner.start()
	end

	local my_task
	my_task = async.run(function()
		local job = async.run(spawn, cmd, env)

		local timeout = config.get().request_timeout
		local ok, stdout, stderr
		if timeout and timeout > 0 then
			-- async.timeout 本身就是 await（返回结果，超时 error('timeout')），用 pcall 捕获
			ok, stdout, stderr = pcall(async.timeout, timeout, job)
		else
			ok, stdout, stderr = async.pawait(job)
		end

		-- 已被更新的请求取代：回收交给新请求，这里直接退出。
		if translate_task ~= my_task then
			return
		end

		-- pcall(async.timeout, ...) 返回时可能处于快速事件上下文（libuv），
		-- 必须先切回主循环（sleep(0) 经 runtime 的 schedule 钩子恢复），
		-- 否则下面的窗口/notify 调用会报 E5560 fast event context。
		async.sleep(0)

		translate_task = nil
		vim.g.translator_status = ""
		spinner.close()

		if not ok then
			util.show_msg("Translation failed: " .. tostring(stdout), "error")
			return
		end

		local out = util.safe_trim(table.concat(stdout or {}, "\n"))
		if out ~= "" then
			handle_stdout(displaymode, options, key, out)
		else
			handle_stderr(displaymode, util.safe_trim(table.concat(stderr or {}, "\n")))
		end
	end)
	translate_task = my_task

	-- 顶层任务是静默的，显式观测失败（忽略取消）。
	-- on_complete 可能在快速上下文中触发，必须切回主循环再调 UI/notify。
	my_task:on_complete(function(err)
		if err == nil or tostring(err):find("closed", 1, true) then
			return
		end
		local message = tostring(err)
		vim.schedule(function()
			util.show_msg("Translation task failed: " .. message, "error")
		end)
	end)
end

return M
