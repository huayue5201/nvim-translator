-- File: lua/translator/targets.lua
-- Extract translatable segments (comments / string literals) from a buffer.
--
-- Tree-sitter is used whenever a parser is attached: it handles heredocs,
-- template literals, raw strings and injected languages (Vue, Markdown code
-- fences) correctly. Without a parser we fall back to a small byte scanner
-- driven by 'commentstring' plus a per-filetype table of extras.

local util = require("translator.util")

local M = {}

--- Filetypes without comments: every non-empty line is a target.
local PLAIN = {
	text = true,
	markdown = true,
	help = true,
	rst = true,
	org = true,
	gitcommit = true,
	gitrebase = true,
}

--- Extra line-comment leaders per filetype (on top of 'commentstring').
local EXTRA_LINE = {
	c = { "//" },
	cpp = { "//" },
	cs = { "//" },
	java = { "//" },
	javascript = { "//" },
	typescript = { "//" },
	javascriptreact = { "//" },
	typescriptreact = { "//" },
	go = { "//" },
	rust = { "//" },
	zig = { "//" },
	php = { "//" },
	swift = { "//" },
	kotlin = { "//" },
	scala = { "//" },
	dart = { "//" },
	jsonc = { "//" },
	arduino = { "//" },
	gdscript = { "#" },
	python = { "#" },
	sh = { "#" },
	bash = { "#" },
	zsh = { "#" },
	fish = { "#" },
	ruby = { "#" },
	perl = { "#" },
	yaml = { "#" },
	toml = { "#" },
	make = { "#" },
	dockerfile = { "#" },
	nginx = { "#" },
	cmake = { "#" },
	elixir = { "#" },
	r = { "#" },
	julia = { "#" },
	tcl = { "#" },
	awk = { "#" },
	purescript = { "--" },
	sql = { "--" },
	haskell = { "--" },
	lua = { "--" },
	vhdl = { "--" },
	ada = { "--" },
	elm = { "--" },
	lisp = { ";" },
	scheme = { ";" },
	clojure = { ";" },
	elisp = { ";" },
	asm = { ";" },
	nasm = { ";" },
	erlang = { "%" },
	tex = { "%" },
	matlab = { "%" },
}

--- Extra block comments per filetype: { open, close, kind }.
local EXTRA_BLOCK = {
	lua = { { "--[[", "]]", "comment" } },
	python = {
		{ '"""', '"""', "string" },
		{ "'''", "'''", "string" },
	},
}

--- Fallback 'commentstring' when ftplugin did not set one.
local FALLBACK_CS = {
	c = "/* %s */",
	cpp = "/* %s */",
	cs = "/* %s */",
	java = "/* %s */",
	javascript = "/* %s */",
	typescript = "/* %s */",
	javascriptreact = "/* %s */",
	typescriptreact = "/* %s */",
	css = "/* %s */",
	scss = "/* %s */",
	php = "/* %s */",
	rust = "/* %s */",
	go = "/* %s */",
	swift = "/* %s */",
	kotlin = "/* %s */",
	scala = "/* %s */",
	dart = "/* %s */",
	jsonc = "/* %s */",
	html = "<!-- %s -->",
	xml = "<!-- %s -->",
	markdown = "<!-- %s -->",
	vue = "<!-- %s -->",
	sql = "-- %s",
	lua = "-- %s",
	python = "# %s",
	sh = "# %s",
	vim = '" %s',
}

local cfgs = {}

local function sort_longest(list)
	table.sort(list, function(a, b)
		return #a > #b
	end)
	return list
end

--- Build (and cache) the fallback scanner config for a buffer.
---@param bufnr integer
---@return table
function M.cfg(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local ft = vim.bo[bufnr].filetype or ""
	local cached = cfgs[bufnr]
	if cached and cached.ft == ft and cached.cs == vim.bo[bufnr].commentstring then
		return cached
	end

	local cs = vim.bo[bufnr].commentstring or ""
	if cs == "" then
		cs = FALLBACK_CS[ft] or ""
	end

	local prefix, suffix = "", ""
	if cs ~= "" then
		local p, s = cs:match("^(.-)%%s(.-)$")
		if p then
			prefix, suffix = util.safe_trim(p), util.safe_trim(s)
		end
	end

	local line, blocks = {}, {}
	if prefix ~= "" then
		if suffix == "" then
			line[1] = prefix
		else
			blocks[1] = { prefix, suffix, "comment" }
		end
	end

	local seen = {}
	for _, l in ipairs(line) do
		seen[l] = true
	end
	for _, l in ipairs(EXTRA_LINE[ft] or {}) do
		if not seen[l] then
			seen[l] = true
			line[#line + 1] = l
		end
	end
	for _, b in ipairs(EXTRA_BLOCK[ft] or {}) do
		blocks[#blocks + 1] = b
	end

	sort_longest(line)
	table.sort(blocks, function(a, b)
		return #a[1] > #b[1]
	end)

	local cfg = { ft = ft, cs = cs, plain = PLAIN[ft] == true, line = line, blocks = blocks, strings = true }
	cfgs[bufnr] = cfg
	return cfg
end

--- True when every non-empty line of this filetype is translatable.
---@param cfg table
---@return boolean
function M.plain(cfg)
	return cfg.plain == true
end

local function add(segs, kind, raw)
	local t = util.safe_trim(raw or "")
	t = t:gsub("^%*+%s*", "")
	if t == "" or not (util.has_cjk(t) or t:match("%a")) then
		return
	end
	if kind == "string" then
		if #t < 2 then
			return
		end
		if not util.has_cjk(t) and #t <= 3 and t:match("^[%w_]+$") then
			return
		end
	end
	segs[#segs + 1] = { text = t, kind = kind }
end

--- Scan a quoted string starting at byte `i`; returns content and next index.
local function scan_string(line, i)
	local q = line:sub(i, i)
	local j = i + 1
	local parts = {}
	while j <= #line do
		local c = line:sub(j, j)
		if c == "\\" then
			parts[#parts + 1] = line:sub(j, j + 1)
			j = j + 2
		elseif c == q then
			return table.concat(parts), j + 1
		else
			parts[#parts + 1] = c
			j = j + 1
		end
	end
	return nil, nil -- unterminated: ignore the rest of the line
end

local function match_at(line, i, pat)
	return line:sub(i, i + #pat - 1) == pat
end

--- Scanner state carried across lines (open block comment).
function M.new_state()
	return { block = nil, kind = nil }
end

--- Extract comment/string segments from one line (fallback scanner).
---@param line string
---@param cfg table
---@param state table
---@return { text:string, kind:string }[]
function M.line(line, cfg, state)
	local segs = {}
	local i = 1

	if state.block then
		local s, e = line:find(state.block, 1, true)
		if s then
			add(segs, state.kind or "comment", line:sub(1, s - 1))
			state.block, state.kind = nil, nil
			i = e + 1
		else
			add(segs, state.kind or "comment", line)
			return segs
		end
	end

	if i == 1 and line:sub(1, 2) == "#!" then
		return segs
	end

	while i <= #line do
		local advanced = false

		for _, b in ipairs(cfg.blocks) do
			if match_at(line, i, b[1]) then
				local s = i + #b[1]
				local q = line:find(b[2], s, true)
				if q then
					add(segs, b[3], line:sub(s, q - 1))
					i = q + #b[2]
				else
					add(segs, b[3], line:sub(s))
					state.block, state.kind = b[2], b[3]
					return segs
				end
				advanced = true
				break
			end
		end

		if not advanced then
			for _, leader in ipairs(cfg.line) do
				if match_at(line, i, leader) then
					add(segs, "comment", line:sub(i + #leader))
					return segs
				end
			end

			local c = line:sub(i, i)
			if cfg.strings and (c == '"' or c == "'" or c == "`") then
				local text, nxt = scan_string(line, i)
				if not text then
					return segs
				end
				add(segs, "string", text)
				i = nxt
				advanced = true
			end
		end

		if not advanced then
			i = i + 1
		end
	end

	return segs
end

---------------------------------------------------------------------
-- Tree-sitter
---------------------------------------------------------------------
local function kind_of(name)
	if name:find("comment", 1, true) then
		return "comment"
	end
	if name:find("string", 1, true) or name:find("heredoc", 1, true) or name:find("char_literal", 1, true) then
		return "string"
	end
	return nil
end

--- Drop comment leaders / string delimiters from one segment line.
local function clean(text, kind, first, last)
	local t = util.safe_trim(text)
	if kind == "comment" then
		if first then
			t = t:gsub("^[-/%#;%*!<>]+%s*", "")
		end
		if last then
			t = t:gsub("%s*[-/%*<>]+$", "")
		end
		return (t:gsub("^%*+%s*", ""))
	end
	if first then
		-- Lua long strings and raw-string prefixes: [[, r#" ...
		t = t:gsub("^[%a]*#*%[=*%[", ""):gsub("^[%a]*#*[\"'`]", "")
	end
	if last then
		t = t:gsub("%]=*%]$", ""):gsub("[\"'`]#?$", "")
	end
	return t
end

local function usable(t, kind)
	if t == "" or not (util.has_cjk(t) or t:match("%a")) then
		return false
	end
	return kind ~= "string" or #t >= 2
end

---@return table<integer, {text:string, kind:string}[]>|nil
local function ts_scan(bufnr, first, last)
	local ok, parser = pcall(vim.treesitter.get_parser, bufnr)
	if not ok or not parser or type(parser.for_each_tree) ~= "function" then
		return nil
	end
	if not pcall(parser.parse, parser) then
		return nil
	end

	local out = {}

	local function visit(node)
		local kind = kind_of(node:type())
		if kind then
			local sr, er = node:range()
			if er >= first - 1 and sr <= last - 1 then
				local rows = vim.split(vim.treesitter.get_node_text(node, bufnr), "\n", { plain = true })
				for i, row in ipairs(rows) do
					local lnum = sr + i
					if lnum >= first and lnum <= last then
						local seg = clean(row, kind, i == 1, i == #rows)
						if usable(seg, kind) then
							out[lnum] = out[lnum] or {}
							table.insert(out[lnum], { text = seg, kind = kind })
						end
					end
				end
			end
			-- Nested nodes (e.g. string_content) would duplicate the segment.
			return
		end
		for child in node:iter_children() do
			if child:named() then
				visit(child)
			end
		end
	end

	local walked = pcall(function()
		parser:for_each_tree(function(tree)
			visit(tree:root())
		end)
	end)
	if not walked then
		return nil
	end
	return out
end

local function fallback_scan(bufnr, first, last, cfg)
	local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
	local state = M.new_state()
	local out = {}
	for i, line in ipairs(lines) do
		local segs = M.line(line, cfg, state)
		if #segs > 0 then
			out[first + i - 1] = segs
		end
	end
	return out
end

--- Collect translatable segments in a line range.
---@param bufnr integer|nil
---@param first integer|nil
---@param last integer|nil
---@return table<integer, {text:string, kind:string}[]>
function M.scan(bufnr, first, last)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	local total = vim.api.nvim_buf_line_count(bufnr)
	first = math.max(1, first or 1)
	last = math.min(total, last or total)
	if first > last then
		return {}
	end

	local cfg = M.cfg(bufnr)
	if cfg.plain then
		local out = {}
		local lines = vim.api.nvim_buf_get_lines(bufnr, first - 1, last, false)
		for i, line in ipairs(lines) do
			local t = util.safe_trim(line)
			if t ~= "" and (util.has_cjk(t) or t:match("%a")) then
				out[first + i - 1] = { { text = t, kind = "text" } }
			end
		end
		return out
	end

	return ts_scan(bufnr, first, last) or fallback_scan(bufnr, first, last, cfg)
end

return M
