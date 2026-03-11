-- FileName: buffer.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Buffer module for translator plugin

local M = {}

-- 创建带边框的缓冲区
function M.create_border(configs)
	local repeat_width = configs.width - 2
	local title_width = vim.fn.strdisplaywidth(configs.title)
	local borderchars = configs.borderchars
	local c_top, c_right, c_bottom, c_left, c_topleft, c_topright, c_botright, c_botleft =
		borderchars[1],
		borderchars[2],
		borderchars[3],
		borderchars[4],
		borderchars[5],
		borderchars[6],
		borderchars[7],
		borderchars[8]

	-- 构建边框内容
	local content = {}
	-- 顶部边框
	table.insert(content, c_topleft .. configs.title .. string.rep(c_top, repeat_width - title_width) .. c_topright)
	-- 中间行
	for _ = 1, configs.height - 2 do
		table.insert(content, c_left .. string.rep(" ", repeat_width) .. c_right)
	end
	-- 底部边框
	table.insert(content, c_botleft .. string.rep(c_bottom, repeat_width) .. c_botright)

	-- TODO:ref:f8fdf7
	local bd_bufnr = M.create_scratch_buf(content)
	vim.api.nvim_buf_set_option(bd_bufnr, "filetype", "translatorborder")
	return bd_bufnr
end

-- 创建临时缓冲区
function M.create_scratch_buf(lines)
	-- 创建缓冲区 (listed=false, scratch=true)
	local bufnr = vim.api.nvim_create_buf(false, true)

	-- 设置缓冲区选项
	vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
	vim.api.nvim_buf_set_option(bufnr, "undolevels", -1)

	-- 如果有提供内容，则写入缓冲区
	if lines and type(lines) == "table" then
		vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
		vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
	end

	return bufnr
end

-- 初始化缓冲区
function M.init(bufnr)
	-- 使用 nvim_buf_set_var 或 setbufvar 设置缓冲区变量
	vim.api.nvim_buf_set_option(bufnr, "filetype", "translator")
	vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
	vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
	vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
	vim.api.nvim_buf_set_option(bufnr, "swapfile", false)

	-- 或者使用 setbufvar（保持与原插件一致）
	-- vim.fn.setbufvar(bufnr, '&filetype', 'translator')
	-- vim.fn.setbufvar(bufnr, '&buftype', 'nofile')
	-- vim.fn.setbufvar(bufnr, '&bufhidden', 'wipe')
	-- vim.fn.setbufvar(bufnr, '&buflisted', 0)
	-- vim.fn.setbufvar(bufnr, '&swapfile', 0)
end

return M
