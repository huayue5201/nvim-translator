-- File: lua/translator/action.lua
-- Modern Neovim-native action module

local util = require("translator.util")
local logger = require("translator.logger")
local window = require("translator.window")

local M = {}

local MARK = "• "

-- Prefix used for the target-language sentence in bilingual mode.
local TARGET_MARK = "↳ "

---------------------------------------------------------------------
-- Bilingual interleave: alternate source sentence / target sentence.
-- When the two sides have different sentence counts, the longer side's
-- extra sentences are appended at the end.
---------------------------------------------------------------------
local function append_bilingual(out, source_text, target_text)
	local src = util.split_sentences(source_text)
	local dst = util.split_sentences(target_text)

	local n = math.max(#src, #dst)
	for i = 1, n do
		if src[i] then
			table.insert(out, src[i])
		end
		if dst[i] then
			table.insert(out, TARGET_MARK .. dst[i])
		end
	end
end

---------------------------------------------------------------------
-- Deduplicate LLM results: models often copy the paraphrase into
-- `explains`, which would show the same translation twice. Collect the
-- paraphrase text (whole + per-sentence) and skip any explain that
-- matches it, ignoring trailing sentence punctuation.
---------------------------------------------------------------------
local function normalize_for_dedup(s)
	s = util.safe_trim(s)
	s = s:gsub("[\r\n]+", " ")
	s = s:gsub("[。！？.!?]+%s*$", "")
	return s
end

local function collect_seen(paraphrase)
	local seen = {}
	if not paraphrase or paraphrase == "" then
		return seen
	end

	local function add(s)
		local k = normalize_for_dedup(s)
		if k ~= "" then
			seen[k] = true
		end
	end

	add(paraphrase)
	for _, s in ipairs(util.split_sentences(paraphrase)) do
		add(s)
	end

	return seen
end

---------------------------------------------------------------------
-- Build window content
---------------------------------------------------------------------
local function build_window_content(trans, options)
	local out = {}

	local bilingual = options and options.bilingual == true

	-- 原文（自动截断）
	local text = trans.text
	if #text > 60 then
		text = text:sub(1, 60) .. "..."
	end
	table.insert(out, "⟦ " .. text .. " ⟧")

	for _, t in ipairs(trans.results) do
		local has_content = (t.paraphrase and t.paraphrase ~= "") or (t.explains and #t.explains > 0)

		if has_content then
			table.insert(out, "")
			table.insert(out, "─── " .. t.engine .. " ───")

			if t.phonetic and t.phonetic ~= "" then
				table.insert(out, MARK .. "[" .. t.phonetic .. "]")
			end

			-- 已展示的译文文本，用于对 explains 去重
			local seen = collect_seen(t.paraphrase)

			if t.paraphrase and t.paraphrase ~= "" then
				if bilingual then
					append_bilingual(out, trans.text, t.paraphrase)
				else
					for line in t.paraphrase:gmatch("[^\r\n]+") do
						table.insert(out, MARK .. util.safe_trim(line))
					end
				end
			end

			if t.explains then
				for _, e in ipairs(t.explains) do
					if type(e) == "string" then
						-- 每条释义可能来自 LLM 且含换行,逐行拆分后作为独立行写入,
						-- 避免 nvim_buf_set_lines 报 "item contains newlines"。
						for line in e:gmatch("[^\r\n]+") do
							local trimmed = util.safe_trim(line)
							if trimmed ~= "" and not seen[normalize_for_dedup(trimmed)] then
								table.insert(out, MARK .. trimmed)
							end
						end
					end
				end
			end
		end
	end

	return out
end

---------------------------------------------------------------------
-- Window display
---------------------------------------------------------------------
function M.window(trans, options)
	local content = build_window_content(trans, options)
	logger.log(content)
	window.open(content)
end

---------------------------------------------------------------------
-- Interactive window display (fixed position, focusable, copy-friendly)
---------------------------------------------------------------------
function M.interactive(trans, options)
	local content = build_window_content(trans, options)
	logger.log(content)
	window.open_interactive(content)
end

---------------------------------------------------------------------
-- Echo display
---------------------------------------------------------------------
function M.echo(trans)
	local text = trans.text
	if #text > 40 then
		text = text:sub(1, 40) .. "..."
	end

	local chunks = {
		{ text, "Function" },
		{ " ==> ", "Constant" },
	}

	-- Show every engine that returned content, separated by a divider.
	local first = true
	for _, t in ipairs(trans.results) do
		local has_content = (t.paraphrase and t.paraphrase ~= "")
			or (t.explains and #t.explains > 0)
			or (t.phonetic and t.phonetic ~= "")

		if has_content then
			if not first then
				table.insert(chunks, { " │ ", "Comment" })
			end
			first = false

			table.insert(chunks, { "[" .. t.engine .. "] ", "Identifier" })

			if t.phonetic and t.phonetic ~= "" then
				table.insert(chunks, { "[" .. t.phonetic .. "] ", "Type" })
			end
			if t.paraphrase and t.paraphrase ~= "" then
				table.insert(chunks, { (t.paraphrase:gsub("[\r\n]+", " ")) .. " ", "Normal" })
			end
			if t.explains and #t.explains > 0 then
				local seen = collect_seen(t.paraphrase)
				local explains = {}
				for _, e in ipairs(t.explains) do
					if type(e) == "string" then
						local dedup = e:gsub("[\r\n]+", " ")
						if not seen[normalize_for_dedup(dedup)] then
							explains[#explains + 1] = dedup
						end
					end
				end
				if #explains > 0 then
					table.insert(chunks, { table.concat(explains, " "), "Normal" })
				end
			end
		end
	end

	vim.api.nvim_echo(chunks, false, {})
end

---------------------------------------------------------------------
-- Replace selected text
---------------------------------------------------------------------
function M.replace(trans)
	local replacement = nil

	for _, t in ipairs(trans.results) do
		if t.paraphrase and t.paraphrase ~= "" then
			replacement = t.paraphrase
			break
		end
	end

	if not replacement then
		util.show_msg("No paraphrase available for replacement", "warning")
		return
	end

	-- 使用 Neovim 原生 API 替换选区
	local mode = vim.api.nvim_get_mode().mode
	local start
	local finish

	if mode:match("^[vV\22]") then
		start = vim.fn.getpos("v")
		finish = vim.fn.getpos(".")
	else
		start = vim.fn.getpos("'<")
		finish = vim.fn.getpos("'>")
	end

	if start[2] == 0 or finish[2] == 0 then
		util.show_msg("No visual selection to replace", "warning")
		return
	end

	local srow = start[2] - 1
	local scol = start[3] - 1
	local erow = finish[2] - 1
	local ecol = finish[3] - 1 -- ← 修复这里

	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end

	-- 统一换行符，避免 LLM 返回 \r\n 时把 \r 写进 buffer
	replacement = replacement:gsub("\r\n", "\n"):gsub("\r", "\n")
	local lines = vim.split(replacement, "\n")

	vim.api.nvim_buf_set_text(0, srow, scol, erow, ecol + 1, lines)
end

return M
