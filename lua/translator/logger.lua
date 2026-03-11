-- FileName: logger.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Logger module for translator plugin

local M = {}

-- 存储日志的数组
local log = {}

function M.init()
	log = {}
end

function M.log(info)
	-- 获取调用栈信息
	local trace = debug.getinfo(2, "Sl").short_src .. ":" .. debug.getinfo(2, "l").currentline
	local log_entry = {}
	log_entry[trace] = info
	table.insert(log, log_entry)
end

function M.open_log()
	-- 垂直分割打开日志窗口
	vim.cmd("bo vsplit vim-translator.log")

	-- 设置缓冲区选项
	vim.bo.buftype = "nofile"
	vim.bo.commentstring = "@ %s"

	-- 添加语法高亮匹配
	vim.fn.matchadd("Constant", "\\v\\@.*$")

	-- 清空当前缓冲区
	vim.cmd("normal! ggdG")

	-- 写入日志内容
	for _, log_entry in ipairs(log) do
		for trace, info in pairs(log_entry) do
			-- 写入追踪信息
			vim.fn.append("$", "@" .. trace)

			-- 根据类型写入信息
			if type(info) == "table" then
				vim.fn.append("$", vim.inspect(info))
			else
				vim.fn.append("$", tostring(info))
			end

			-- 添加空行分隔
			vim.fn.append("$", "")
		end
	end

	-- 移动到文件开头
	vim.cmd("normal! gg")
end

return M
