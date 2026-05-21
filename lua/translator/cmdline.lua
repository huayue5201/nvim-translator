-- File: lua/translator/cmdline.lua
-- Modern Neovim-native command line parser for translator.nvim

local util = require("translator.util")
local M = {}

---------------------------------------------------------------------
-- Parse command line arguments
---------------------------------------------------------------------
function M.parse(bang, range, line1, line2, argstr)
	local opts = {
		text = "",
		engines = {},
		source_lang = "",
		target_lang = "",
	}

	-------------------------------------------------------------------
	-- Split arguments safely
	-------------------------------------------------------------------
	local args = vim.split(argstr or "", "%s+", { trimempty = true })
	local texts = {}

	for _, arg in ipairs(args) do
		if arg:match("^%-%-") then
			local key, val = arg:match("^%-%-(.-)=(.+)$")
			if key and val then
				if key == "engines" then
					opts.engines = vim.split(val, ",", { trimempty = true })
				else
					opts[key] = val
				end
			end
		else
			-- Collect non-flag arguments as text
			table.insert(texts, arg)
		end
	end

	opts.text = table.concat(texts, " ")

	-------------------------------------------------------------------
	-- If no text provided, use visual selection
	-------------------------------------------------------------------
	opts.text = opts.text ~= "" and opts.text or (util.get_visual_selection() or "")
	opts.text = util.text_proc(opts.text)
	if opts.text == "" then
		return nil
	end

	-------------------------------------------------------------------
	-- Defaults
	-------------------------------------------------------------------
	-- Handle engines: global default or fallback
	opts.engines = opts.engines or {}
	if #opts.engines == 0 then
		opts.engines = vim.g.translator_default_engines or { "google" }
		if type(opts.engines) == "string" then
			opts.engines = vim.split(opts.engines, ",", { trimempty = true })
		end
	end

	-- Source/target language defaults
	opts.source_lang = opts.source_lang ~= "" and opts.source_lang or vim.g.translator_source_lang or "auto"
	opts.target_lang = opts.target_lang ~= "" and opts.target_lang or vim.g.translator_target_lang or "zh"

	-------------------------------------------------------------------
	-- Bang (!) swaps languages
	-------------------------------------------------------------------
	if bang then
		opts.source_lang, opts.target_lang = opts.target_lang, opts.source_lang
	end

	return opts
end
---------------------------------------------------------------------
-- Command completion
---------------------------------------------------------------------
function M.complete(arg_lead, cmd_line, cursor_pos)
	local options = {
		"--engines=",
		"--source_lang=",
		"--target_lang=",
	}

	local engines = { "bing", "google", "haici", "youdao", "iciba", "sdcv", "trans" }

	local before = cmd_line:sub(1, cursor_pos)
	local args = vim.split(before, "%s+", { trimempty = true })
	table.remove(args, 1) -- remove command name

	if #args == 0 then
		return options
	end

	local last = args[#args]

	-- Complete engines list
	if last:match("^%-%-engines=") then
		local prefix = last:match("^%-%-engines=(.*)$") or ""
		local used = vim.split(prefix, ",", { trimempty = true })

		local unused = {}
		for _, e in ipairs(engines) do
			local found = false
			for _, u in ipairs(used) do
				if u == e then
					found = true
				end
			end
			if not found then
				table.insert(unused, e)
			end
		end

		local base = "--engines=" .. (prefix:match("^(.*,)") or "")
		local out = {}
		for _, e in ipairs(unused) do
			table.insert(out, base .. e)
		end
		return out
	end

	-- Complete option keys
	local out = {}
	for _, opt in ipairs(options) do
		if opt:find(last, 1, true) == 1 then
			table.insert(out, opt)
		end
	end

	return out
end

return M
