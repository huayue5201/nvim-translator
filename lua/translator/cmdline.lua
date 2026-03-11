-- FileName: cmdline.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Command line module for translator plugin

local util = require("translator.util")
local logger = require("translator.logger")

local M = {}

-- 查找最后一个匹配位置
local function match_last_pos(expr, pat)
	local pos = -1
	local start = 1
	while true do
		local p = string.find(expr, pat, start, true) -- true 表示 plain 匹配
		if not p then
			break
		end
		pos = p
		start = p + 1
	end
	return pos
end

function M.parse(bang, range, line1, line2, argstr)
	logger.log(argstr)

	local options = {
		text = "",
		engines = {},
		target_lang = "",
		source_lang = "",
	}

	local arglist = vim.fn.split(argstr)

	if #arglist > 0 then
		local c = 0
		for i, arg in ipairs(arglist) do
			if string.match(arg, "^%-%-.+%=.+$") then -- 匹配 --xxx=yyy 格式
				local opt = vim.fn.split(arg, "=")
				if #opt ~= 2 then
					util.show_msg("Argument Error: No value given to option: " .. opt[1], "error")
					return nil
				end
				local key = string.sub(opt[1], 3) -- 去掉开头的 '--'
				local value = opt[2]

				if key == "engines" then
					options.engines = vim.fn.split(value, ",")
				else
					options[key] = value
				end
				c = c + 1
			else
				-- 剩余部分都是文本
				options.text = table.concat(arglist, " ", c + 1)
				break
			end
		end
	end

	-- 如果没有提供文本，从可视选择获取
	if options.text == "" then
		options.text = util.visual_select(range, line1, line2)
	end

	options.text = util.text_proc(options.text)
	if options.text == "" then
		return nil
	end

	-- 设置默认值
	if #options.engines == 0 then
		options.engines = vim.g.translator_default_engines or { "google" }
	end

	if options.target_lang == "" then
		options.target_lang = vim.g.translator_target_lang or "zh"
	end

	if options.source_lang == "" then
		options.source_lang = vim.g.translator_source_lang or "auto"
	end

	-- 如果使用了 !，交换源语言和目标语言
	if bang and options.source_lang ~= "auto" then
		options.source_lang, options.target_lang = options.target_lang, options.source_lang
	end

	return options
end

function M.complete(arg_lead, cmd_line, cursor_pos)
	local opts_key = { "--engines=", "--target_lang=", "--source_lang=" }
	local candidates = vim.tbl_map(function(key)
		return key
	end, opts_key) -- 复制一份

	-- 获取光标前的命令行
	local cmd_line_before_cursor = string.sub(cmd_line, 1, cursor_pos)
	local args = vim.fn.split(cmd_line_before_cursor, "\\v\\@<!(\\\\\\\\)*\\zs\\s+", 1)
	table.remove(args, 1) -- 移除命令名

	-- 移除已经使用的选项
	for _, key in ipairs(opts_key) do
		if string.find(cmd_line_before_cursor, key, 1, true) then
			for i, k in ipairs(candidates) do
				if k == key then
					table.remove(candidates, i)
					break
				end
			end
		end
	end

	-- 如果没有参数，返回所有候选
	if #args == 0 then
		return candidates
	end

	local prefix = args[#args]

	if prefix == "" then
		return candidates
	end

	local engines = { "bing", "google", "haici", "iciba", "sdcv", "trans", "youdao" }

	-- 处理逗号分隔的引擎补全
	if string.find(prefix, ",", 1, true) then
		local pos = match_last_pos(prefix, ",")
		local preprefix = string.sub(prefix, 1, pos)

		-- 找出未使用的引擎
		local unused_engines = {}
		for _, e in ipairs(engines) do
			if not string.find(prefix, e, 1, true) then
				table.insert(unused_engines, e)
			end
		end

		-- 构建候选
		candidates = {}
		for _, e in ipairs(unused_engines) do
			table.insert(candidates, preprefix .. e)
		end
	elseif string.find(prefix, "--engines=", 1, true) then
		-- 补全引擎名
		candidates = {}
		for _, e in ipairs(engines) do
			table.insert(candidates, "--engines=" .. e)
		end
	end

	-- 过滤匹配前缀的候选
	local result = {}
	for _, candidate in ipairs(candidates) do
		if string.sub(candidate, 1, #prefix) == prefix then
			table.insert(result, candidate)
		end
	end

	return result
end

return M
