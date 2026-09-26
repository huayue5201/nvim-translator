-- File: lua/translator/util.lua
-- Description: Pure Neovim utility functions for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Message helpers
---------------------------------------------------------------------
function M.show_msg(message, msg_type)
	local msg = type(message) == "string" and message or vim.inspect(message)
	local prefix = "[translator] "

	if msg_type == "error" then
		vim.api.nvim_echo({ { prefix, "ErrorMsg" }, { msg } }, false, {})
	elseif msg_type == "warning" then
		vim.api.nvim_echo({ { prefix, "WarningMsg" }, { msg } }, false, {})
	else
		vim.api.nvim_echo({ { prefix, "Constant" }, { msg } }, false, {})
	end
end

---------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------
function M.safe_trim(text)
	return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---------------------------------------------------------------------
-- Normalize text before sending to the backend (argv, no shell quoting).
---------------------------------------------------------------------
function M.text_proc(text)
	local t = text:gsub("\n", " ")
	t = t:gsub("\r", " ")
	t = t:gsub("^%s+", "")
	t = t:gsub("%s+$", "")
	return t
end

---------------------------------------------------------------------
-- CJK detection. Lua patterns are byte-based, so we match UTF-8 byte
-- ranges directly:
--   Han (CJK Unified Ideographs) U+4E00–9FFF -> E4 80 80 – E9 BF BF
--   Hiragana / Katakana          U+3040–30FF -> E3 81 80 – E3 83 BF
--   Hangul syllables             U+AC00–D7AF -> EA B0 80 – ED 9E AF
---------------------------------------------------------------------
local function has_han(text)
	return text ~= nil and text ~= "" and text:find("[\228-\233][\128-\191][\128-\191]") ~= nil
end

local function has_kana(text)
	return text ~= nil and text ~= "" and text:find("[\227][\129-\131][\128-\191]") ~= nil
end

local function has_hangul(text)
	return text ~= nil and text ~= "" and text:find("[\234-\237][\128-\191][\128-\191]") ~= nil
end

--- True if the text contains any CJK character (Han / kana / Hangul).
function M.has_cjk(text)
	return has_han(text) or has_kana(text) or has_hangul(text)
end

--- Classify CJK text as "ko" (Hangul), "ja" (kana) or "zh" (Han), or nil
--- when the text is not CJK. Kana and Hangul are decisive; Han alone is
--- treated as Chinese (Japanese text virtually always contains kana, and
--- modern Korean text is Hangul).
function M.detect_cjk(text)
	if has_hangul(text) then
		return "ko"
	end
	if has_kana(text) then
		return "ja"
	end
	if has_han(text) then
		return "zh"
	end
	return nil
end

---------------------------------------------------------------------
-- Split text into sentences, keeping the terminating punctuation.
-- Handles both Latin (. ! ?) and fullwidth CJK (。！？) terminators.
-- ASCII terminators only split when followed by whitespace/end, to avoid
-- breaking decimals ("3.14") and abbreviations ("Mr. Smith").
---------------------------------------------------------------------
function M.split_sentences(text)
	if not text or text == "" then
		return {}
	end

	text = text:gsub("[\r\n\t]+", " ")
	text = text:gsub("%s+", " ")

	local sentences = {}
	local buf = ""

	local function flush()
		buf = M.safe_trim(buf)
		if buf ~= "" then
			table.insert(sentences, buf)
		end
		buf = ""
	end

	local function peek(i)
		if i > #text then
			return ""
		end
		local b = text:byte(i)
		if b >= 0xE0 and b <= 0xEF then
			return text:sub(i, i + 2)
		elseif b >= 0xC0 and b <= 0xDF then
			return text:sub(i, i + 1)
		end
		return text:sub(i, i)
	end

	local i = 1
	while i <= #text do
		local b = text:byte(i)
		local ch
		if b >= 0xE0 and b <= 0xEF then
			ch = text:sub(i, i + 2)
			i = i + 3
		elseif b >= 0xC0 and b <= 0xDF then
			ch = text:sub(i, i + 1)
			i = i + 2
		else
			ch = text:sub(i, i)
			i = i + 1
		end

		buf = buf .. ch

		local is_cjk_term = (ch == "。" or ch == "！" or ch == "？")
		local is_ascii_term = (ch == "." or ch == "!" or ch == "?")

		if is_cjk_term then
			flush()
		elseif is_ascii_term then
			local next_ch = peek(i)
			if next_ch == "" or next_ch == " " then
				flush()
			end
		end
	end

	flush()

	return sentences
end

---------------------------------------------------------------------
-- Center padding
---------------------------------------------------------------------
function M.pad(text, width, char)
	local text_width = vim.fn.strdisplaywidth(text)
	local pad_size = math.max(0, width - text_width)

	local left = math.floor(pad_size / 2)
	local right = pad_size - left

	return string.rep(char, left) .. text .. string.rep(char, right)
end

---------------------------------------------------------------------
-- Wrap long lines
---------------------------------------------------------------------
function M.wrap_line(line, width)
	if vim.fn.strdisplaywidth(line) <= width then
		return { line }
	end

	local words = {}

	for word in line:gmatch("%S+%s*") do
		table.insert(words, word)
	end

	local lines = {}
	local current_line = ""

	for _, word in ipairs(words) do
		local test_line

		if current_line == "" then
			test_line = word
		else
			test_line = current_line .. word
		end

		if vim.fn.strdisplaywidth(test_line) <= width then
			current_line = test_line
		else
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			current_line = word
		end
	end

	if current_line ~= "" then
		table.insert(lines, current_line)
	end

	return lines
end

---------------------------------------------------------------------
-- Fit lines for window rendering
---------------------------------------------------------------------
function M.fit_lines(lines, width)
	local result = {}

	for _, line in ipairs(lines) do
		if line:match("^───") then
			local w = vim.fn.strdisplaywidth(line)

			if w < width then
				table.insert(result, M.pad(line, width, "─"))
			else
				table.insert(result, line)
			end
		elseif line:match("^⟦") then
			local w = vim.fn.strdisplaywidth(line)

			if w < width then
				table.insert(result, M.pad(line, width, " "))
			else
				table.insert(result, line)
			end
		else
			local wrapped = M.wrap_line(line, width - 4)

			for _, wrapped_line in ipairs(wrapped) do
				table.insert(result, "  " .. wrapped_line)
			end
		end
	end

	return result
end

---------------------------------------------------------------------
-- Visual selection (v / V / CTRL-V)
---------------------------------------------------------------------
local function manual_visual_selection(mode, start_pos, end_pos)
	local srow = start_pos[2]
	local scol = start_pos[3]
	local erow = end_pos[2]
	local ecol = end_pos[3]

	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end

	local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)

	if #lines == 0 then
		return ""
	end

	if mode == "V" then
		return table.concat(lines, "\n")
	elseif mode == "\22" then
		local result = {}

		for _, line in ipairs(lines) do
			local line_len = #line

			local start_col = math.min(scol, line_len + 1)
			local end_col = math.min(ecol, line_len)

			if start_col <= end_col then
				table.insert(result, line:sub(start_col, end_col))
			else
				table.insert(result, "")
			end
		end

		return table.concat(result, "\n")
	elseif #lines == 1 then
		return lines[1]:sub(scol, ecol)
	else
		local result_lines = {}

		result_lines[1] = lines[1]:sub(scol)

		for i = 2, #lines - 1 do
			table.insert(result_lines, lines[i])
		end

		if #lines > 1 then
			table.insert(result_lines, lines[#lines]:sub(1, ecol))
		end

		return table.concat(result_lines, "\n")
	end
end

function M.get_visual_selection()
	local mode = vim.api.nvim_get_mode().mode
	local start_pos
	local end_pos
	local vmode

	if mode:match("^[vV\22]") then
		-- Active visual mode (e.g. a v-mode keymap): the selection spans the
		-- 'v' mark and the cursor. The '< '> marks are not set yet here.
		vmode = mode
		start_pos = vim.fn.getpos("v")
		end_pos = vim.fn.getpos(".")
	else
		-- :command invoked from visual mode: mode is already "n", but
		-- visualmode() still reports the type and '< '> are set.
		vmode = vim.fn.visualmode()
		if vmode == "" then
			return ""
		end
		start_pos = vim.fn.getpos("'<")
		end_pos = vim.fn.getpos("'>")
	end

	if not start_pos or not end_pos or start_pos[2] == 0 or end_pos[2] == 0 then
		return ""
	end

	-- Prefer getregion() (Neovim 0.10+), it handles multibyte correctly.
	if vim.fn.getregion then
		local ok, region = pcall(vim.fn.getregion, start_pos, end_pos, { type = vmode })
		if ok and type(region) == "table" and #region > 0 then
			return table.concat(region, "\n")
		end
	end

	return manual_visual_selection(vmode, start_pos, end_pos)
end

---------------------------------------------------------------------
-- Extract text from the editing context: visual selection -> line range
-- -> current line -> word under cursor.
---------------------------------------------------------------------
function M.get_text_from_context(opts)
	if opts.range > 0 then
		local s = vim.fn.getpos("'<")
		local e = vim.fn.getpos("'>")
		if s[2] == opts.line1 and e[2] == opts.line2 then
			local sel = M.get_visual_selection()
			if sel ~= "" then
				return sel
			end
		end
	end

	if opts.range == 0 then
		return vim.fn.expand("<cword>")
	elseif opts.range == 1 then
		return vim.api.nvim_get_current_line()
	else
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		return table.concat(lines, "\n")
	end
end

return M
