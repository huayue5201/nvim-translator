-- File: lua/translator/code.lua
-- Extract the code context around the cursor (or the visual selection) for
-- :TranslateExplain. Prefers Tree-sitter (innermost enclosing function, else
-- class-like container), and falls back to indentation-based block detection.

local M = {}

-- Upper bound on the snippet sent to the LLM, to keep token usage sane.
local MAX_LINES = 160

local function indent_width(line)
	local ws = line:match("^%s*") or ""
	local w = 0
	for i = 1, #ws do
		w = w + (ws:byte(i) == 9 and 4 or 1)
	end
	return w
end

local function is_blank(line)
	return line:match("^%s*$") ~= nil
end

local function slice(lines, first, last, row)
	first = math.max(0, first)
	last = math.min(#lines - 1, last)
	if last < first then
		return ""
	end

	-- Too long: keep a window centred on the cursor instead of the head.
	if last - first + 1 > MAX_LINES then
		first = math.max(first, (row or first) - math.floor(MAX_LINES / 3))
		last = math.min(last, first + MAX_LINES - 1)
		first = math.max(0, last - MAX_LINES + 1)
	end

	return table.concat(lines, "\n", first + 1, last + 1)
end

----------------------------------------------------------------------
-- Tree-sitter: climb to the innermost enclosing function/container.
----------------------------------------------------------------------
local function is_function_type(t)
	if t:find("call", 1, true) or t:find("declarator", 1, true) or t:find("type", 1, true) then
		return false
	end
	return t:find("function", 1, true) ~= nil
		or t:find("method", 1, true) ~= nil
		or t:find("lambda", 1, true) ~= nil
		or t:find("closure", 1, true) ~= nil
		or t:find("constructor", 1, true) ~= nil
end

local function is_container_type(t)
	return t:find("class", 1, true) ~= nil
		or t:find("struct", 1, true) ~= nil
		or t:find("interface", 1, true) ~= nil
		or t:find("impl", 1, true) ~= nil
		or t:find("trait", 1, true) ~= nil
		or t:find("enum", 1, true) ~= nil
		or t:find("module", 1, true) ~= nil
		or t:find("namespace", 1, true) ~= nil
end

local function ts_range(row, col)
	local function query()
		local ok, node = pcall(vim.treesitter.get_node, { bufnr = 0, pos = { row, col } })
		return ok and node or nil
	end

	local node = query()
	if not node then
		-- The parser may not be attached/started yet (e.g. headless usage).
		local ok, parser = pcall(vim.treesitter.get_parser, 0)
		if ok and parser then
			pcall(parser.parse, parser)
			node = query()
		end
	end
	if not node then
		return nil
	end

	local func, container
	local n = node
	while n do
		local t = n:type()
		if not func and is_function_type(t) then
			func = n
		end
		if not container and is_container_type(t) then
			container = n
		end
		n = n:parent()
	end

	local target = func or container
	if not target or not target:parent() then
		-- Ignore the root node (e.g. a whole Python module): it is too broad.
		return nil
	end

	local sr, _, er, ec = target:range()
	if er < sr then
		return nil
	end
	-- Tree-sitter's end position is exclusive: an end_col of 0 means the
	-- final row is not part of the node, while end_col > 0 includes it.
	local last = (ec == 0) and (er - 1) or er
	if last < sr then
		return nil
	end
	return sr, last
end

----------------------------------------------------------------------
-- Fallback: indentation. Find the nearest enclosing block head, then take
-- every following line that is more indented than it.
----------------------------------------------------------------------
local function is_closer(line)
	local t = line:match("^%s*(.-)%s*$")
	return t == "end" or t:match("^end[%s%),;]") ~= nil or t:match("^[%)%]}]+[,;]?$") ~= nil
end

local function indent_range(lines, row)
	if #lines == 0 then
		return nil
	end
	row = math.min(row, #lines - 1)

	local probe = row
	while probe > 0 and is_blank(lines[probe + 1]) do
		probe = probe - 1
	end

	local head = probe
	local head_indent = indent_width(lines[head + 1])

	for i = probe - 1, 0, -1 do
		local l = lines[i + 1]
		if not is_blank(l) then
			local ind = indent_width(l)
			if ind < head_indent then
				head = i
				head_indent = ind
				break
			end
		end
	end

	local last = head
	for i = head + 1, #lines - 1 do
		local l = lines[i + 1]
		if not is_blank(l) and indent_width(l) <= head_indent then
			break
		end
		last = i
	end

	-- Keep the block's closing `end` / `}` / `)` so the snippet is complete.
	local after = lines[last + 2]
	if after and is_closer(after) then
		last = last + 1
	end

	return head, last
end

----------------------------------------------------------------------
-- Public: return the snippet text for the current cursor / selection.
----------------------------------------------------------------------
function M.context(opts)
	opts = opts or {}
	local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

	-- Visual selection (or explicit :range): use it verbatim.
	if (opts.range or 0) > 0 then
		local ok, util = pcall(require, "translator.util")
		if ok then
			local sel = util.get_visual_selection()
			if sel ~= "" then
				return sel
			end
		end
		local l1 = opts.line1 or 1
		local l2 = opts.line2 or l1
		return slice(lines, l1 - 1, l2 - 1, math.floor((l1 + l2) / 2) - 1)
	end

	local pos = vim.api.nvim_win_get_cursor(0)
	local row, col = pos[1] - 1, pos[2]

	local first, last = ts_range(row, col)
	if not first then
		first, last = indent_range(lines, row)
	end

	if not first then
		first = math.max(0, row - 10)
		last = math.min(#lines - 1, row + 20)
	elseif last == first then
		-- A single line is rarely enough to understand: widen around it.
		first = math.max(0, math.min(first, row - 8))
		last = math.min(#lines - 1, math.max(last, row + 16))
	end

	return slice(lines, first, last, row)
end

return M
