-- FileName: popup.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Popup window module for translator plugin (Neovim floating window version)

local buffer = require("translator.buffer")
local window = require("translator.window") -- 需要先实现这个模块

local M = {}

-- 弹窗过滤器函数
local function popup_filter(winid, key)
	if key == "<C-k>" then
		-- 向上滚动 - 使用 vim.api.nvim_input 发送按键
		vim.api.nvim_win_call(winid, function()
			vim.api.nvim_input("<C-y>")
		end)
		return true
	elseif key == "<C-j>" then
		-- 向下滚动
		vim.api.nvim_win_call(winid, function()
			vim.api.nvim_input("<C-e>")
		end)
		return true
	elseif key == "q" or key == "x" then
		-- 关闭窗口
		vim.api.nvim_win_close(winid, true)
		return true
	end
	return false
end

function M.create(linelist, configs)
	-- 计算窗口位置
	local cursor = vim.api.nvim_win_get_cursor(0)
	local cursor_line = cursor[1] -- 1-based
	local cursor_col = cursor[2] -- 0-based

	-- 根据 anchor 确定位置
	local anchor = configs.anchor or "top-left"
	local row_offset = 0
	if anchor:find("^top") then
		row_offset = 1 -- 光标下方
	else
		row_offset = -1 -- 光标上方
	end

	-- 创建浮动窗口配置
	local opts = {
		relative = "cursor",
		width = configs.width - 2, -- 减去边框宽度
		height = configs.height,
		row = row_offset,
		col = 0,
		style = "minimal",
		border = {
			{ "┌", "TranslatorBorder" },
			{ "─", "TranslatorBorder" },
			{ "┐", "TranslatorBorder" },
			{ "│", "TranslatorBorder" },
			{ "┘", "TranslatorBorder" },
			{ "─", "TranslatorBorder" },
			{ "└", "TranslatorBorder" },
			{ "│", "TranslatorBorder" },
		},
		borderhighlight = { "TranslatorBorder" },
		zindex = 32000,
	}

	-- 如果有自定义边框字符，使用它们
	if configs.borderchars then
		local bc = configs.borderchars
		opts.border = {
			{ bc[5] or "┌", "TranslatorBorder" }, -- topleft
			{ bc[1] or "─", "TranslatorBorder" }, -- top
			{ bc[6] or "┐", "TranslatorBorder" }, -- topright
			{ bc[2] or "│", "TranslatorBorder" }, -- right
			{ bc[7] or "┘", "TranslatorBorder" }, -- botright
			{ bc[3] or "─", "TranslatorBorder" }, -- bottom
			{ bc[8] or "└", "TranslatorBorder" }, -- botleft
			{ bc[4] or "│", "TranslatorBorder" }, -- left
		}
	end

	-- 创建缓冲区并写入内容
	local bufnr = buffer.create_scratch_buf(linelist)

	-- 创建浮动窗口
	local winid = vim.api.nvim_open_win(bufnr, false, opts)

	-- 初始化窗口（需要先实现 window.lua）
	if window and window.init then
		window.init(winid)
	end

	-- 初始化缓冲区
	buffer.init(bufnr)

	-- 设置键盘映射
	local mappings = {
		["<C-k>"] = function()
			popup_filter(winid, "<C-k>")
		end,
		["<C-j>"] = function()
			popup_filter(winid, "<C-j>")
		end,
		["q"] = function()
			popup_filter(winid, "q")
		end,
		["x"] = function()
			popup_filter(winid, "x")
		end,
	}

	for key, callback in pairs(mappings) do
		vim.api.nvim_buf_set_keymap(bufnr, "n", key, "", {
			callback = callback,
			noremap = true,
			silent = true,
			nowait = true,
		})
	end

	return winid
end

return M
