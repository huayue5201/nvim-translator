-- File: lua/translator/inline.lua
-- Virtual-text bilingual mode: each source line gets its translation drawn as
-- a virtual line *below* it (extmark `virt_lines`). The buffer itself is never
-- modified, so editing / undo / syntax stay untouched.
--
--   :TranslateV          toggle for the whole buffer
--   :'<,'>TranslateV      toggle for the selected lines
--   :TranslateVClear      remove every virtual translation

local util = require("translator.util")
local cache = require("translator.cache")
local config = require("translator.config")
local binary = require("translator.binary")
local cmdline = require("translator.cmdline")

local M = {}

local NS = vim.api.nvim_create_namespace("translator_inline")

--- bufnr -> session { bufnr, bin, env, engines, source_lang, target_lang,
---   proxy, force, queue, running, concurrency, stopped, hl, marks }
local sessions = {}

local function inline_cfg()
	return config.get().inline or {}
end

local function hl_group()
	local g = require("translator.highlight").group_for("inline")
	return g
end

local function ensure_augroup()
	local aug = vim.api.nvim_create_augroup("translator_inline", { clear = false })
	if vim.g.translator_inline_aug then
		return
	end
	vim.g.translator_inline_aug = true
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		callback = function(args)
			M.clear(args.buf)
		end,
	})
end

---------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------
local function render(sess, lnum, translation)
	local bufnr = sess.bufnr
	if sess.stopped or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end
	local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""

	-- Keep indentation so the translation lines up under the source line.
	local indent = line:match("^[ \t]*") or ""
	local chunks = { { indent .. translation, sess.hl or "TranslatorInline" } }

	local ok, mark = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, 0, {
		virt_lines = { chunks },
		virt_lines_above = false,
	})
	if ok then
		sess.marks[lnum] = mark
	end
end

---------------------------------------------------------------------
-- Result extraction
---------------------------------------------------------------------
local function pick_translation(decoded)
	if type(decoded) ~= "table" then
		return nil
	end
	for _, t in ipairs(decoded.results or {}) do
		if type(t) == "table" then
			if type(t.paraphrase) == "string" and vim.trim(t.paraphrase) ~= "" then
				return vim.trim((t.paraphrase:gsub("[\r\n]+", " ")))
			end
			if type(t.explains) == "table" and #t.explains > 0 then
				local parts = {}
				for _, e in ipairs(t.explains) do
					if type(e) == "string" and vim.trim(e) ~= "" then
						parts[#parts + 1] = vim.trim((e:gsub("[\r\n]+", " ")))
					end
				end
				if #parts > 0 then
					return table.concat(parts, "；")
				end
			end
		end
	end
	return nil
end

---------------------------------------------------------------------
-- Job queue (bounded concurrency; one backend process per line)
---------------------------------------------------------------------
local start_next

function start_next(sess)
	if sess.stopped then
		return
	end
	while sess.running < sess.concurrency and #sess.queue > 0 do
		local item = table.remove(sess.queue, 1)
		local options = {
			text = item.text,
			engines = sess.engines,
			source_lang = sess.source_lang,
			target_lang = sess.target_lang,
		}
		local key = cache.key(options, sess.env)

		local cached = (not sess.force) and cache.get(key) or nil
		if cached then
			local tr = pick_translation(cached)
			if tr and util.safe_trim(item.text):lower() ~= tr:lower() then
				render(sess, item.lnum, tr)
			end
		else
			sess.running = sess.running + 1

			local cmd = {
				sess.bin,
				"translate",
				"--target_lang",
				sess.target_lang,
				"--source_lang",
				sess.source_lang,
				"--engines",
				table.concat(sess.engines, ","),
			}
			if sess.proxy and sess.proxy ~= "" then
				table.insert(cmd, "--proxy")
				table.insert(cmd, sess.proxy)
			end
			table.insert(cmd, item.text)

			local stdout, stderr = {}, {}
			local id
			id = vim.fn.jobstart(cmd, {
				env = sess.env,
				stdout_buffered = true,
				stderr_buffered = true,
				on_stdout = function(_, data)
					stdout = data or {}
				end,
				on_stderr = function(_, data)
					stderr = data or {}
				end,
				on_exit = function()
					local out, err = stdout, stderr
					vim.schedule(function()
						sess.running = math.max(0, sess.running - 1)
						sess.jobs[id] = nil
						if sess.stopped then
							return
						end

						local raw = util.safe_trim(table.concat(out or {}, "\n"))
						if raw ~= "" then
							local ok, decoded = pcall(vim.json.decode, raw)
							local tr = ok and pick_translation(decoded) or nil
							if tr and cache.has_content(decoded) then
								cache.set(key, decoded)
							end
							if tr then
								local src = util.safe_trim(item.text)
								if src:lower() ~= tr:lower() then
									render(sess, item.lnum, tr)
								end
							end
						elseif #err > 0 and sess.warned ~= true then
							sess.warned = true
							util.show_msg("虚拟翻译失败：" .. util.safe_trim(table.concat(err, " ")), "error")
						end

						start_next(sess)
					end)
				end,
			})
			if id <= 0 then
				sess.running = math.max(0, sess.running - 1)
				util.show_msg("无法启动翻译后端", "error")
				return
			end
			sess.jobs[id] = true
		end
	end
end

---------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------
--- Whether a virtual-text session exists for the buffer.
---@param bufnr integer|nil
---@return boolean
function M.active(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	return sessions[bufnr] ~= nil
end

--- Remove virtual translations for one buffer (stops in-flight jobs).
---@param bufnr integer|nil
function M.clear(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local sess = sessions[bufnr]
	if sess then
		sess.stopped = true
		for id in pairs(sess.jobs) do
			pcall(vim.fn.jobstop, id)
		end
		sess.jobs = {}
		sess.queue = {}
		sessions[bufnr] = nil
	end
	if vim.api.nvim_buf_is_valid(bufnr) then
		vim.api.nvim_buf_clear_namespace(bufnr, NS, 0, -1)
	end
end

--- Remove virtual translations for every buffer.
function M.clear_all()
	for bufnr in pairs(sessions) do
		M.clear(bufnr)
	end
end

--- Translate the current buffer (or the given range) and show the result as
--- virtual lines. Any previous session for the buffer is replaced.
---@param opts table|nil user-command opts ({ range, line1, line2, args })
function M.translate(opts)
	opts = opts or {}

	local bufnr = vim.api.nvim_get_current_buf()
	local bin = binary.get()
	if not bin then
		return
	end

	local first, last
	if (opts.range or 0) > 0 then
		first, last = opts.line1, opts.line2
	else
		first, last = 1, vim.api.nvim_buf_line_count(bufnr)
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	if #lines == 0 then
		return
	end

	local max_lines = tonumber(inline_cfg().max_lines) or 200
	if (opts.range or 0) == 0 and #lines > max_lines then
		util.show_msg(
			string.format(
				"缓冲区有 %d 行，超过上限 %d；请先用可视选区指定范围",
				#lines,
				max_lines
			),
			"warning"
		)
		return
	end

	-- Reuse the normal command parser for engines / direction / flags, with
	-- the whole block as the language-detection sample.
	local parsed = cmdline.parse({
		args = opts.args or "",
		range = 0,
		line1 = 1,
		line2 = 1,
		text = table.concat(lines, "\n"),
	})
	if not parsed then
		return
	end

	-- Fresh session (drops the previous one for this buffer).
	M.clear(bufnr)
	ensure_augroup()

	local sess = {
		bufnr = bufnr,
		bin = bin,
		env = require("translator").backend_env(),
		engines = parsed.engines,
		source_lang = parsed.source_lang,
		target_lang = parsed.target_lang,
		proxy = config.get().proxy_url,
		force = parsed.force == true,
		concurrency = math.max(1, tonumber(inline_cfg().concurrency) or 4),
		queue = {},
		jobs = {},
		running = 0,
		stopped = false,
		marks = {},
		hl = hl_group(),
	}
	sessions[bufnr] = sess

	for i, line in ipairs(lines) do
		local trimmed = util.safe_trim(line)
		-- Skip blanks and lines with no letters / CJK (punctuation, symbols).
		if trimmed ~= "" and (util.has_cjk(trimmed) or trimmed:match("%a")) then
			table.insert(sess.queue, { lnum = first + i - 1, text = trimmed })
		end
	end

	if #sess.queue == 0 then
		sessions[bufnr] = nil
		util.show_msg("没有可翻译的文本行", "warning")
		return
	end

	start_next(sess)
end

--- Toggle virtual bilingual display for the current buffer.
---@param opts table|nil
function M.toggle(opts)
	local bufnr = vim.api.nvim_get_current_buf()
	if M.active(bufnr) then
		M.clear(bufnr)
	else
		M.translate(opts)
	end
end

return M
