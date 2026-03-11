-- FileName: preview.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Preview window module for translator plugin

local buffer = require("translator.buffer")
local util = require("translator.util")

local M = {}

-- 模块级变量，存储窗口ID
local winid = -1

local function win_exists(win_id)
	return vim.fn.getwininfo(win_id) and #vim.fn.getwininfo(win_id) > 0
end

local function win_close_preview()
	local current_win = vim.api.nvim_get_current_win()
	if current_win == winid then
		return
	else
		if win_exists(winid) then
			-- 尝试关闭窗口
			pcall(vim.api.nvim_win_close, winid, true)
		end
		-- 清除自动命令组
		pcall(vim.api.nvim_del_augroup_by_name, "close_translator_window")
	end
	winid = -1
end

function M.create(linelist, configs)
	-- 关闭已存在的预览窗口
	win_close_preview()

	-- 保存当前位置
	local curr_pos = vim.fn.getpos(".")

	-- 在 Neovim 中，我们用浮动窗口模拟预览窗口
	-- 计算窗口位置（在屏幕中央偏右的位置）
	local ui = vim.api.nvim_list_uis()[1]
	local width = configs.width or 60
	local height = configs.height or 10

	-- 预览窗口通常位于右侧
	local opts = {
		relative = "editor",
		width = width,
		height = height,
		col = ui.width - width - 10, -- 距离右侧10列
		row = math.floor((ui.height - height) / 2), -- 垂直居中
		style = "minimal",
		border = "rounded",
		zindex = 32000,
	}

	-- 创建缓冲区并写入内容
	local bufnr = buffer.create_scratch_buf(linelist)
	buffer.init(bufnr)

	-- 创建浮动窗口
	winid = vim.api.nvim_open_win(bufnr, false, opts)

	-- 设置窗口为预览窗口风格
	vim.api.nvim_win_set_option(winid, "winhighlight", "Normal:Normal")

	-- 初始化窗口（需要实现 window.lua）
	-- require('translator.window').init(winid)

	-- 回到原来的窗口
	vim.api.nvim_set_current_win(0)

	-- 设置自动命令组，用于自动关闭
	local augroup = vim.api.nvim_create_augroup("close_translator_window", { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI", "InsertEnter", "BufLeave" }, {
		group = augroup,
		buffer = 0, -- 当前缓冲区
		callback = function()
			vim.defer_fn(win_close_preview, 100)
		end,
	})

	return winid
end

return M
