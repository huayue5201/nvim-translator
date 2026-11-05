-- File: lua/translator/targets.lua
-- Extract translatable "targets" (comments and string literals) from a line.
--
-- This is a regex/byte-scanner fallback, not a full parser: it knows the
-- buffer's 'commentstring', a few extra comment leaders for common filetypes,
-- same-or-multi-line block comments and quoted strings with backslash escapes.
-- Good enough for comment translation; a Tree-sitter backend could replace it
-- later without changing the API.

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

--- Build (and cache) the target config for a buffer.
---@param bufnr integer
---@return table { plain:boolean, line:string[], blocks:{open:string,close:string,kind:string}[], strings:boolean }
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

	local line = {}
	local blocks = {}

	if prefix ~= "" then
		if suffix == "" then
			line[#line + 1] = prefix
		else
			blocks[#blocks + 1] = { prefix, suffix, "comment" }
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

	local cfg = {
		ft = ft,
		cs = cs,
		plain = PLAIN[ft] == true,
		line = line,
		blocks = blocks,
		strings = true,
	}
	cfgs[bufnr] = cfg
	return cfg
end

function M.new_state()
	return { block = nil, kind = nil }
end

--- True when every non-empty line of this filetype is translatable.
function M.plain(cfg)
	return cfg.plain == true
end

local function add(segs, kind, raw)
	local t = util.safe_trim(raw or "")
	-- Block-comment continuation lines usually start with "*".
	t = t:gsub("^%*+%s*", "")
	if t == "" then
		return
	end
	if not (util.has_cjk(t) or t:match("%a")) then
		return
	end
	if kind == "string" then
		-- Skip one-byte char literals and tiny identifier-like values.
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

--- Extract comment/string segments from one line.
---@param line string
---@param cfg table from M.cfg
---@param state table from M.new_state (block-comment carry-over)
---@return { text:string, kind:string }[]
function M.line(line, cfg, state)
	local segs = {}
	state = state or M.new_state()

	local i = 1

	-- Finish a block comment opened on an earlier line.
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

	-- Shebang: never translate.
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

return M
