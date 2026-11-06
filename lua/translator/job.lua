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
local proc = require("translator.proc")
local cancel = require("translator.cancel")

local async = vim.async

local M = {}

-- 在途翻译任务：新请求会取消它（中止子进程 + 回收 spinner）
local translate_task = nil
-- 当前在途请求的取消句柄，供 cancel 模块登记/注销。
local current_abort = nil

---------------------------------------------------------------------
-- Apply a (fresh or cached) translation result: state + display + history.
---------------------------------------------------------------------
function M.apply_result(displaymode, translations, options)
	state.set(translations, options)

	-- 未知模式一律按窗口处理：只有显式 "replace" 才允许改写 buffer。
	if displaymode == "replace" then
		action.replace(translations, options)
	elseif displaymode == "interactive" then
		action.interactive(translations, options)
	else
		action.window(translations, options)
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
	state.set(translations, options)
	history.save(translations)
	llm_server.mark_active()
end

---------------------------------------------------------------------------------------------------------------------------------------
-- Run one backend request; returns (stdout, stderr) when the job exits.
--
-- Text travels over stdin so it never shows up in `ps` and long selections
-- cannot hit the argv size limit.
---------------------------------------------------------------------
local function spawn(cmd, env, stdin)
	local res = proc.run(cmd, { env = env, stdin = stdin })
	return res.stdout, res.stderr
end

---------------------------------------------------------------------
-- Streaming backend request: NDJSON, one translated engine per line.
-- `on_line` is called (on the main loop) for each complete line; the
-- await resolves with stderr when the process exits.
---------------------------------------------------------------------
local function spawn_stream(cmd, env, stdin, on_line)
	return async.await(function(done)
		local line_buf = ""
		local stopped = false

		local function feed(chunk)
			line_buf = line_buf .. chunk
			while true do
				local nl = line_buf:find("\n", 1, true)
				if not nl then
					break
				end
				local line = line_buf:sub(1, nl - 1)
				line_buf = line_buf:sub(nl + 1)
				if line ~= "" then
					on_line(line)
				end
			end
		end

		local system = vim.system(cmd, {
			env = env,
			stdin = stdin,
			text = true,
			[proc.STDOUT_KEY] = function(_, data)
				if data and not stopped then
					vim.schedule(function()
						if not stopped then
							feed(data)
						end
					end)
				end
			end,
		}, function(res)
			vim.schedule(function()
				if not stopped and line_buf ~= "" then
					on_line(line_buf)
					line_buf = ""
				end
				done(vim.trim(res.stderr or ""))
			end)
		end)

		return {
			close = function(_, callback)
				stopped = true
				pcall(system.kill, system, 15)
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
-- 所有引擎都没内容时，把每个引擎的失败原因拼成一行，避免只显示
-- 笼统的 “Translation failed”。后端为每个失败引擎带 `error` 字段。
local function failure_summary(translations)
	local parts = {}
	for _, t in ipairs((translations and translations.results) or {}) do
		if type(t) == "table" then
			local reason = t.error
			if type(reason) ~= "string" or reason == "" then
				reason = "no result"
			end
			parts[#parts + 1] = tostring(t.engine or "?") .. ": " .. reason
		end
	end
	if #parts == 0 then
		return "no engine returned a result"
	end
	return table.concat(parts, " | ")
end

local function handle_stdout(displaymode, options, key, message)
	logger.log(message)

	local ok, translations = pcall(vim.json.decode, message)
	if not ok or not translations then
		util.show_msg("Translation failed: invalid response from backend", "error")
		return
	end

	-- 所有引擎都失败时后端仍会输出合法 JSON（空 results），这类结果
	-- 不能写入缓存，否则之后重试会一直命中这个空结果。
	if not cache.has_content(translations) then
		util.show_msg("Translation failed — " .. failure_summary(translations), "error")
		return
	end

	-- 先写缓存，这样重复请求可以完全跳过后端。
	cache.set(key, translations)
	M.apply_result(displaymode, translations, options)
end

local function handle_stderr(message)
	logger.log(message)
	util.show_msg(message, "error")
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
function M.jobstart(cmd, stdin, displaymode, env, options, key)
	if current_abort then
		cancel.unregister(current_abort)
		current_abort = nil
	end
	if translate_task then
		translate_task:close()
	end

	vim.g.translator_status = "translating"

	-- 请求延时期间在光标处显示旋转提示（可用 config.spinner.enable 关闭）。
	if config.get().spinner.enable ~= false then
		spinner.start()
	end

	local streaming = stream_enabled(displaymode)

	if streaming then
		-- insert right after the subcommand ("translate"), before option flags
		table.insert(cmd, 3, "--stream")
	end

	local my_task

	-- 请求一发出就能中止：即使流式窗口还没弹出（首条结果未到），<Esc>
	-- 也必须生效。浮窗打开后，窗口内的局部 <Esc> 映射优先于全局映射。
	local function abort()
		if current_abort ~= abort then
			return
		end
		current_abort = nil
		cancel.unregister(abort)

		vim.g.translator_status = ""
		spinner.close()
		-- 关闭流式骨架窗口（buffered 模式下无窗口，close 为安全 no-op）。
		require("translator.window").close()
		if translate_task then
			local task = translate_task
			translate_task = nil
			task:close()
		end
	end

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

			local job = async.run(spawn_stream, cmd, env, stdin, on_line)

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
			current_abort = nil
			cancel.unregister(abort)
			vim.g.translator_status = ""
			spinner.close()

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
				util.show_msg("Translation failed — " .. failure_summary(trans), "error")
			end
			return
		end

		-- ===== buffered mode =====
		local job = async.run(spawn, cmd, env, stdin)

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
		current_abort = nil
		cancel.unregister(abort)
		vim.g.translator_status = ""
		spinner.close()

		if not ok then
			util.show_msg("Translation failed: " .. tostring(stdout), "error")
			return
		end

		local out = util.safe_trim(stdout or "")
		if out ~= "" then
			handle_stdout(displaymode, options, key, out)
		else
			handle_stderr(util.safe_trim(stderr or ""))
		end
	end)
	translate_task = my_task
	current_abort = abort
	cancel.register(abort)

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
-- Cancel the in-flight request (and any other registered async work).
---------------------------------------------------------------------
---@return boolean whether something was in flight
function M.cancel()
	local in_flight = current_abort ~= nil
	cancel.cancel()
	return in_flight
end

return M
