-- File: lua/translator/cmdline.lua
-- Modern Neovim-native command line parser for translator.nvim

local util = require("translator.util")
local M = {}

function M.parse(opts)
	local options = {
		text = "",
		engines = {},
		source_lang = "",
		target_lang = "",
	}

	-------------------------------------------------------------------
	-- Split arguments: --key=value flags vs. plain text
	-------------------------------------------------------------------
	local args = vim.split(opts.args or "", "%s+", { trimempty = true })
	local texts = {}

	for _, arg in ipairs(args) do
		if arg:match("^%-%-") then
			local key, val = arg:match("^%-%-(.-)=(.+)$")
			if key and val then
				if key == "engines" then
					options.engines = vim.split(val, ",", { trimempty = true })
				else
					options[key] = val
				end
			end
		else
			table.insert(texts, arg)
		end
	end

	options.text = table.concat(texts, " ")

	-------------------------------------------------------------------
	-- Fall back to visual selection / range / cword when no text given
	-------------------------------------------------------------------
	if options.text == "" then
		options.text = util.get_text_from_context(opts)
	end

	options.text = util.text_proc(options.text)
	if options.text == "" then
		return nil
	end

	-------------------------------------------------------------------
	-- Defaults
	-------------------------------------------------------------------
	if #options.engines == 0 then
		options.engines = vim.g.translator_default_engines or { "google" }
		if type(options.engines) == "string" then
			options.engines = vim.split(options.engines, ",", { trimempty = true })
		end
	end

	-------------------------------------------------------------------
	-- Language direction: auto-detected unless explicitly overridden
	-------------------------------------------------------------------
	local explicit_lang = options.source_lang ~= "" or options.target_lang ~= ""

	if not explicit_lang then
		-- Auto direction: CJK text -> zh→en, otherwise -> auto→zh.
		if util.has_cjk(options.text) then
			options.source_lang = "zh"
			options.target_lang = "en"
		else
			options.source_lang = "auto"
			options.target_lang = "zh"
		end
	else
		options.source_lang = options.source_lang ~= ""
				and options.source_lang
			or vim.g.translator_source_lang
			or "auto"
		options.target_lang = options.target_lang ~= ""
				and options.target_lang
			or vim.g.translator_target_lang
			or "zh"

		-- Bang (!) swaps languages
		if opts.bang then
			options.source_lang, options.target_lang = options.target_lang, options.source_lang
		end
	end

	return options
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

	local engines = {
		"api",
		"baicizhan",
		"baidu",
		"bing",
		"google",
		"haici",
		"iciba",
		"llm",
		"sdcv",
		"trans",
		"youdao",
	}

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
