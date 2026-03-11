-- FileName: history.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: History module for translator plugin

local util = require("translator.util")

local M = {}

-- 获取历史文件路径
local function get_history_file_path()
	-- 获取当前文件的绝对路径，然后向上找到项目根目录
	local current_file = debug.getinfo(1, "S").source:sub(2) -- 去掉开头的 '@'
	local history_file = current_file:gsub("lua/translator/history.lua$", "translation_history.data")
	return history_file
end

local history_file = get_history_file_path() -- 改名为 history_file，不使用 s: 前缀

local function padding_end(text, length)
	local result = tostring(text)
	local len = vim.fn.strchars(result)
	if len < length then
		result = result .. string.rep(" ", length - len)
	end
	return result
end

function M.save(translations)
	-- 检查是否启用历史记录
	if not vim.g.translator_history_enable then
		return
	end

	local text = translations["text"]
	local item = nil

	-- 遍历结果，找到合适的记录项
	for _, t in ipairs(translations["results"]) do
		local paraphrase = t["paraphrase"]
		local explains = t["explains"]

		if explains and #explains > 0 then
			item = padding_end(text, 25) .. explains[1]
			break
		elseif paraphrase and paraphrase ~= "" and text:lower() ~= paraphrase:lower() then
			item = padding_end(text, 25) .. paraphrase
			break
		else
			return
		end
	end

	if not item then
		return
	end

	-- 确保文件存在
	if vim.fn.filereadable(history_file) == 0 then
		vim.fn.writefile({}, history_file)
	end

	-- 读取现有历史记录
	local trans_data = vim.fn.readfile(history_file)

	-- 检查是否已存在
	for _, line in ipairs(trans_data) do
		if line:find(vim.pesc(text), 1, true) then
			return
		end
	end

	-- 追加新记录
	local file = io.open(history_file, "a")
	if file then
		file:write(item .. "\n")
		file:close()
	end
end

function M.export()
	if vim.fn.filereadable(history_file) == 0 then
		util.show_msg("History file not exist yet", "error")
		return
	end

	-- 在新标签页中打开历史文件
	vim.cmd("tabnew " .. history_file)
	vim.bo.filetype = "translator_history"

	-- 设置语法高亮
	vim.cmd([[
        syn match TranslateHistoryQuery #\v^.*\v%25v#
        syn match TranslateHistoryTrans #\v%26v.*$#
        hi def link TranslateHistoryQuery Keyword
        hi def link TranslateHistoryTrans String
    ]])
end

return M
