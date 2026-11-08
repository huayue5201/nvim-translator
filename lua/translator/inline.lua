-- File: lua/translator/inline.lua
-- Buffer-internal bilingual view (:TranslateV): translations are rendered as
-- virtual lines under their source line, so the buffer itself is never
-- modified and no extra window steals focus.
--
-- Only comments / string literals are translated (see translator.targets);
-- plain-text filetypes translate every non-empty line. Edits to the buffer
-- trigger a debounced re-translation.

local batch = require("translator.batch")
local cancel = require("translator.cancel")
local binary = require("translator.binary")
local cache = require("translator.cache")
local cmdline = require("translator.cmdline")
local config = require("translator.config")
local highlight = require("translator.highlight")
local targets = require("translator.targets")
local util = require("translator.util")

local M = {}

local NS = vim.api.nvim_create_namespace("translator_inline")
local sessions = {}
local attached = {}
local aug = nil

local function inline_cfg()
	return config.get().inline or {}
end

local function hl_group()
	return highlight.group_for("inline")
end

local function ensure_augroup()
	if aug then
		return
	end
	aug = vim.api.nvim_create_augroup("translator_inline", { clear = true })
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		callback = function(args)
			M.clear(args.buf)
		end,
	})

	-- Re-translate after edits: extmark positions drift otherwise, and stale
	-- translations would stay attached to the wrong line. on_lines also sees
	-- API-driven changes (TextChanged does not).
	vim.api.nvim_create_autocmd("BufWipeout", {
		group = aug,
		callback = function(args)
			M.clear(args.buf)
		end,
	})
end

local function attach(bufnr)
	attached[bufnr] = true
	vim.api.nvim_buf_attach(bufnr, false, {
		on_lines = function()
			M.schedule_refresh(bufnr)
			return sessions[bufnr] == nil
		end,
		on_detach = function()
			attached[bufnr] = nil
			sessions[bufnr] = nil
		end,
	})
end

---------------------------------------------------------------------
-- Rendering
---------------------------------------------------------------------
--- Re-render the virtual lines for one source line from sess.results.
local function render(sess, lnum)
	local bufnr = sess.bufnr
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	if sess.marks[lnum] then
		pcall(vim.api.nvim_buf_del_extmark, bufnr, NS, sess.marks[lnum])
		sess.marks[lnum] = nil
	end

	local res = sess.results[lnum]
	if not res then
		return
	end

	local indexes = vim.tbl_keys(res)
	table.sort(indexes)
	if #indexes == 0 then
		return
	end

	local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1] or ""
	local indent = line:match("^[ \t]*") or ""
	local virt_lines = {}
	for _, idx in ipairs(indexes) do
		virt_lines[#virt_lines + 1] = { { indent .. res[idx], sess.hl or "TranslatorInline" } }
	end

	local ok, mark = pcall(vim.api.nvim_buf_set_extmark, bufnr, NS, lnum - 1, 0, {
		virt_lines = virt_lines,
		virt_lines_above = false,
	})
	if ok then
		sess.marks[lnum] = mark
	end
end

--- Record one translated segment and refresh its line.
local function store(sess, item, translation)
	if not translation or translation == "" then
		return
	end
	if util.safe_trim(item.text):lower() == translation:lower() then
		return
	end
	sess.results[item.lnum] = sess.results[item.lnum] or {}
	sess.results[item.lnum][item.idx] = translation
	render(sess, item.lnum)
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
-- Public API
---------------------------------------------------------------------
--- Whether a virtual-text session exists for the buffer.
---@param bufnr integer|nil
---@return boolean
function M.active(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	return sessions[bufnr] ~= nil
end

--- Remove virtual translations for one buffer (stops in-flight work).
---@param bufnr integer|nil
function M.clear(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local sess = sessions[bufnr]
	if sess then
		sess.done = true
		if sess.cancel then
			cancel.unregister(sess.cancel)
			sess.cancel = nil
		end
		if sess.timer then
			sess.timer:stop()
			sess.timer:close()
		end
		if sess.proc then
			pcall(sess.proc.kill, sess.proc, 15)
		end
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

--- Debounced re-translation after a buffer edit.
---@param bufnr integer
function M.schedule_refresh(bufnr)
	local sess = sessions[bufnr]
	if not sess or not sess.origin then
		return
	end
	sess.timer = sess.timer or vim.uv.new_timer()
	sess.timer:stop()
	sess.timer:start(400, 0, function()
		vim.schedule(function()
			if sessions[bufnr] ~= sess or not vim.api.nvim_buf_is_valid(bufnr) then
				return
			end
			M.translate(sess.origin)
		end)
	end)
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
				"Buffer has %d lines, exceeding the limit of %d; select a range in visual mode first",
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

	M.clear(bufnr)
	ensure_augroup()

	local sess = {
		bufnr = bufnr,
		env = require("translator").backend_env(),
		engines = parsed.engines,
		source_lang = parsed.source_lang,
		target_lang = parsed.target_lang,
		proxy = config.get().proxy_url,
		force = parsed.force == true,
		concurrency = math.max(1, tonumber(inline_cfg().concurrency) or 4),
		origin = { range = opts.range or 0, line1 = first, line2 = last, args = opts.args },
		marks = {},
		results = {},
		hl = hl_group(),
	}
	sessions[bufnr] = sess
	if not attached[bufnr] then
		attach(bufnr)
	end

	local segs = targets.scan(bufnr, first, last)
	local lnums = vim.tbl_keys(segs)
	table.sort(lnums)

	local items = {}
	for _, lnum in ipairs(lnums) do
		for idx, seg in ipairs(segs[lnum]) do
			items[#items + 1] = {
				lnum = lnum,
				idx = idx,
				text = (seg.text:gsub("[\r\n]+", " ")), -- one text per stdin line
				kind = seg.kind,
			}
		end
	end

	if #items == 0 then
		sessions[bufnr] = nil
		local why = targets.plain(targets.cfg(bufnr)) and "No lines of text to translate"
			or "No translatable comments or strings found"
		util.show_msg(why, "warning")
		return
	end

	-- Serve cache hits immediately; everything else goes out as one batch.
	local pending, texts = {}, {}
	for _, item in ipairs(items) do
		item.key = cache.key({
			text = item.text,
			engines = sess.engines,
			source_lang = sess.source_lang,
			target_lang = sess.target_lang,
		}, sess.env)

		local cached = (not sess.force) and cache.get(item.key) or nil
		local translation = cached and pick_translation(cached)
		if translation then
			store(sess, item, translation)
		else
			pending[#pending + 1] = item
			texts[#texts + 1] = item.text
		end
	end

	if #pending == 0 then
		return
	end

	-- <Esc> stops the batch; lines translated so far stay on screen.
	local function finish()
		sess.done = true
		sess.proc = nil
		if sess.cancel then
			cancel.unregister(sess.cancel)
			sess.cancel = nil
		end
	end
	sess.cancel = function()
		if sess.done then
			return
		end
		if sess.proc then
			pcall(sess.proc.kill, sess.proc, 15)
		end
		finish()
	end
	sess.remaining = #pending
	cancel.register(sess.cancel)

	sess.proc = batch.start(
		bin,
		sess.env,
		{
			engines = sess.engines,
			source_lang = sess.source_lang,
			target_lang = sess.target_lang,
			proxy = sess.proxy,
			concurrency = sess.concurrency,
		},
		texts,
		{
			on_result = function(id, decoded)
				if sess.done then
					return
				end
				local item = pending[id + 1] -- `id` is the 0-based index into `texts`
				if not item or sessions[bufnr] ~= sess then
					return
				end
				if cache.has_content(decoded) then
					cache.set(item.key, decoded)
				end
				store(sess, item, pick_translation(decoded))
				sess.remaining = sess.remaining - 1
				if sess.remaining <= 0 then
					finish()
				end
			end,
			on_error = function(message)
				if sess.done then
					return
				end
				finish()
				if sess.warned or sessions[bufnr] ~= sess then
					return
				end
				sess.warned = true
				util.show_msg("Virtual translation failed: " .. message, "error")
			end,
		}
	)
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
