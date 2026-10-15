-- File: lua/translator/job.lua

local logger = require("translator.logger")
local action = require("translator.action")
local history = require("translator.history")
local util = require("translator.util")
local state = require("translator.state")
local cache = require("translator.cache")
local config = require("translator.config")
local spinner = require("translator.spinner")
local llm_server = require("translator.llm_server")

local async = vim.async

local M = {}

-- 最近一次成功翻译的结果（仅用于 echo 模式下报错时的回显）
local stdout_save = nil

-- 在途翻译任务：新请求会取消它（中止子进程 + 回收 spinner）
local translate_task = nil

---------------------------------------------------------------------
-- Cancel key: while a request is in flight, temporarily bind a key
-- (default <Esc>) to abort it. Only the modes the user hasn't already
-- mapped are touched, and the binding is removed once the request settles.
---------------------------------------------------------------------
local cancel_key_modes = {} -- modes where we installed the bind

local function cancel_key()
	local key = config.get().cancel_key
	if key == nil then
		return "<Esc>"
	end
	return key
end

local function install_cancel_key()
	local key = cancel_key()
	if key == false or key == "" then
		return
	end
	local opts = { silent = true, nowait = true, desc = "Cancel translation" }
	for _, mode in ipairs({ "n", "v" }) do
		if not cancel_key_modes[mode] and vim.fn.maparg(key, mode) == "" then
			vim.keymap.set(mode, key, function()
				M.cancel()
			end, opts)
			cancel_key_modes[mode] = true
		end
	end
end

local function remove_cancel_key()
	local key = cancel_key()
	for _, mode in ipairs({ "n", "v" }) do
		if cancel_key_modes[mode] then
			pcall(vim.keymap.del, mode, key)
			cancel_key_modes[mode] = nil
		end
	end
end

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

	-- 本地 LLM 服务：记录活跃时间戳，供 watchdog 判断空闲回收。
	llm_server.mark_active()
end

---------------------------------------------------------------------
-- Commit a result whose display was already produced incrementally
-- (state + cache-less bookkeeping only; no window re-open).
---------------------------------------------------------------------
local function commit_result(translations, options)
	stdout_save = translations
	state.set(translations, options)
	history.save(translations)
	llm_server.mark_active()
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
-- Streaming backend request: NDJSON, one translated engine per line.
-- `on_line` is called (on the main loop) for each complete line; the
-- await resolves with stderr when the process exits.
---------------------------------------------------------------------
local function spawn_stream(cmd, env, on_line)
	return async.await(function(done)
		local stderr = {}
		local line_buf = ""
		local stopped = false

		local opts = {
			stderr_buffered = true,
			on_stdout = function(_, data)
				if stopped then
					return
				end
				line_buf = line_buf .. table.concat(data or {}, "\n")
				while true do
					local nl = line_buf:find("\n", 1, true)
					if not nl then
						break
					end
					local line = line_buf:sub(1, nl - 1)
					line_buf = line_buf:sub(nl + 1)
					if line ~= "" then
						vim.schedule(function()
							on_line(line)
						end)
					end
				end
			end,
			on_stderr = function(_, data)
				stderr = data or {}
			end,
			on_exit = function()
				local err = stderr
				vim.schedule(function()
					if not stopped and line_buf ~= "" then
						on_line(line_buf)
						line_buf = ""
					end
					done(err)
				end)
			end,
		}
		if env then
			opts.env = env
		end

		local id = vim.fn.jobstart(cmd, opts)
		if id <= 0 then
			done({ "failed to start translation backend" })
			return nil
		end

		return {
			close = function(_, callback)
				stopped = true
				pcall(vim.fn.jobstop, id)
				if callback then
					callback()
				end
			end,
		}
	end)
end

---------------------------------------------------------------------
-- Result handling (buffered mode)
---------------------------------------------------------------------
local function handle_stdout(displaymode, options, key, message)
	logger.log(message)

	local ok, translations = pcall(vim.json.decode, message)
	if not ok or not translations then
		util.show_msg("Translation failed", "error")
		return
	end

	-- 所有引擎都失败时后端仍会输出合法 JSON（空 results），这类结果
	-- 不能写入缓存，否则之后重试会一直命中这个空结果。
	if not cache.has_content(translations) then
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
-- Incremental (streaming) display support
---------------------------------------------------------------------
-- Only the window-based displays can be filled progressively.
local function stream_enabled(displaymode)
	if config.get().incremental == false then
		return false
	end
	if displaymode ~= "window" and displaymode ~= "interactive" then
		return false
	end
	return (config.get().window.type or "float") ~= "preview"
end

-- Start a streaming result set: empty; engines are appended in arrival order.
local function build_stream_trans(options)
	return {
		text = options.text or "",
		status = 1,
		results = {},
		pending_count = #(options.engines or {}),
	}
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

	local streaming = stream_enabled(displaymode)

	-- 流式模式下浮窗自身处理 <Esc>（cancel-aware），避免与默认 cancel_key
	-- 重复绑定导致互相覆盖。非默认 cancel_key 仍照常临时绑定。
	local ck = cancel_key()
	if not (streaming and ck == "<Esc>") then
		install_cancel_key()
	end

	if streaming then
		-- insert right after the subcommand ("translate"), before option flags
		table.insert(cmd, 3, "--stream")
	end

	local my_task
	my_task = async.run(function()
		-- 按需启动本地 LLM 服务（llama-server 等），已运行则秒回。
		llm_server.ensure()

		if streaming then
			local trans = build_stream_trans(options)
			local seen = {}
			local opened = false

			-- 增量显示：不预建槽位。首个结果到达才弹出浮窗，之后按“到达顺序”
			-- 追加并在原地增高；等待期间只保留光标 spinner。
			local function on_line(line)
				local ok, t = pcall(vim.json.decode, line)
				if not ok or type(t) ~= "table" or not t.engine then
					return
				end
				if not seen[t.engine] then
					seen[t.engine] = true
					trans.results[#trans.results + 1] = t
				else
					for i, r in ipairs(trans.results) do
						if r.engine == t.engine then
							trans.results[i] = t
						end
					end
				end
				local arrived = 0
				for _ in pairs(seen) do
					arrived = arrived + 1
				end
				trans.pending_count = math.max(0, #(options.engines or {}) - arrived)

				if not opened then
					opened = true
					spinner.close()
					action.stream_begin(trans, options, displaymode)
				else
					action.stream_update(trans, options, displaymode)
				end
			end

			local job = async.run(spawn_stream, cmd, env, on_line)

			local timeout = config.get().request_timeout
			local ok, stderr
			if timeout and timeout > 0 then
				-- async.timeout 本身就是 await（返回结果，超时 error('timeout')），用 pcall 捕获
				ok, stderr = pcall(async.timeout, timeout, job)
			else
				ok, stderr = async.pawait(job)
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
			remove_cancel_key()

			if not ok then
				util.show_msg("Translation failed: " .. tostring(stderr), "error")
				return
			end

			-- finalize: 去掉“还有 N 个翻译中…”进度行（只对已弹出的窗口）。
			trans.pending_count = 0
			if opened then
				action.stream_update(trans, options, displaymode)
			end

			if cache.has_content(trans) then
				cache.set(key, trans)
				commit_result(trans, options)
			else
				util.show_msg("Translation failed", "error")
			end
			return
		end

		-- ===== buffered mode =====
		local job = async.run(spawn, cmd, env)

		local timeout = config.get().request_timeout
		local ok, stdout, stderr
		if timeout and timeout > 0 then
			ok, stdout, stderr = pcall(async.timeout, timeout, job)
		else
			ok, stdout, stderr = async.pawait(job)
		end

		-- 已被更新的请求取代：回收交给新请求，这里直接退出。
		if translate_task ~= my_task then
			return
		end

		async.sleep(0)

		translate_task = nil
		vim.g.translator_status = ""
		spinner.close()
		remove_cancel_key()

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

---------------------------------------------------------------------
-- Cancel the in-flight request: abort the child process, close the
-- (possibly still-streaming) window, drop the spinner, reset status and
-- remove the temporary cancel key.
---------------------------------------------------------------------
---@return boolean whether a request was actually in flight
function M.cancel()
	remove_cancel_key()
	vim.g.translator_status = ""
	spinner.close()

	local task = translate_task
	translate_task = nil

	-- 关闭流式骨架窗口（buffered 模式下无窗口，close 为安全 no-op）。
	require("translator.window").close()

	if not task then
		return false
	end

	task:close()
	return true
end

return M
