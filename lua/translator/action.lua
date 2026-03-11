-- FileName: action.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Action module for translator plugin

local util = require("translator.util")
local logger = require("translator.logger")
local window = require("translator.window")

local M = {}

local MARKER = "• "

function M.window(translations)
	local content = {}

	-- 处理原文，如果太长就截断
	local text = translations["text"]
	if #text > 30 then
		text = string.sub(text, 1, 30) .. "..."
	end
	table.insert(content, string.format("⟦ %s ⟧", text))

	-- 遍历每个翻译引擎的结果
	for _, t in ipairs(translations["results"]) do
		-- 如果 paraphrase 和 explains 都为空，跳过
		if (not t.paraphrase or t.paraphrase == "") and (not t.explains or #t.explains == 0) then
			goto continue
		end

		table.insert(content, "")
		table.insert(content, string.format("─── %s ───", t.engine))

		-- 添加音标
		if t.phonetic and t.phonetic ~= "" then
			local phonetic = MARKER .. string.format("[%s]", t.phonetic)
			table.insert(content, phonetic)
		end

		-- 添加释义
		if t.paraphrase and t.paraphrase ~= "" then
			table.insert(content, MARKER .. t.paraphrase)
		end

		-- 添加解释列表
		if t.explains and #t.explains > 0 then
			for _, expl in ipairs(t.explains) do
				local trimmed = util.safe_trim(expl)
				if trimmed ~= "" then
					table.insert(content, MARKER .. trimmed)
				end
			end
		end

		::continue::
	end

	logger.log(content)
	window.open(content)
end

function M.echo(translations)
	local phonetic = ""
	local paraphrase = ""
	local explains = ""

	-- 从第一个非空的结果中获取信息
	for _, t in ipairs(translations["results"]) do
		if t.phonetic and t.phonetic ~= "" and phonetic == "" then
			phonetic = string.format("[%s]", t.phonetic)
		end
		if t.paraphrase and t.paraphrase ~= "" and paraphrase == "" then
			paraphrase = t.paraphrase
		end
		if t.explains and #t.explains > 0 and explains == "" then
			explains = table.concat(t.explains, " ")
		end
	end

	-- 处理原文，如果太长就截断
	local text = translations["text"]
	if #text > 30 then
		text = string.sub(text, 1, 30) .. "..."
	end

	-- 在命令行显示
	util.echo("Function", text)
	util.echon("Constant", "==>")
	util.echon("Type", phonetic)
	util.echon("Normal", paraphrase)
	util.echon("Normal", explains)
end

function M.replace(translations)
	-- 查找第一个非空的 paraphrase 替换选中文本
	for _, t in ipairs(translations["results"]) do
		if t.paraphrase and t.paraphrase ~= "" then
			-- 保存寄存器 a 的当前值
			local reg_tmp = vim.fn.getreg("a")
			local reg_type = vim.fn.getregtype("a")

			-- 将 paraphrase 放入寄存器 a
			vim.fn.setreg("a", t.paraphrase, "c")

			-- 替换选中的文本
			vim.cmd('normal! gv"ap')

			-- 恢复寄存器 a
			vim.fn.setreg("a", reg_tmp, reg_type)

			return
		end
	end

	-- 如果没有找到可替换的内容
	util.show_msg("No paraphrases for the replacement", "warning")
end

return M
