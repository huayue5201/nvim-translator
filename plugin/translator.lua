-- FileName: translator.lua
-- FilePath: plugin/translator.lua
-- Description: Main plugin file for translator.nvim

if vim.g.loaded_translator then
	return
end
vim.g.loaded_translator = 1

-- ==================================================
-- 默认配置
-- ==================================================

-- 历史记录开关
vim.g.translator_history_enable = vim.g.translator_history_enable ~= nil and vim.g.translator_history_enable or false

-- 代理设置
vim.g.translator_proxy_url = vim.g.translator_proxy_url or ""

-- 语言设置
vim.g.translator_source_lang = vim.g.translator_source_lang or "auto"
vim.g.translator_target_lang = vim.g.translator_target_lang or "zh"

-- translate shell 选项（用于 'trans' 引擎）
vim.g.translator_translate_shell_options = vim.g.translator_translate_shell_options or {}

-- 窗口边框字符
vim.g.translator_window_borderchars = vim.g.translator_window_borderchars
	or {
		"─",
		"│",
		"─",
		"│",
		"┌",
		"┐",
		"┘",
		"└",
	}

-- 窗口最大高度/宽度
vim.g.translator_window_max_height = vim.g.translator_window_max_height or 999
vim.g.translator_window_max_width = vim.g.translator_window_max_width or 999

-- 窗口类型
vim.g.translator_window_type = vim.g.translator_window_type or "popup"

-- 根据目标语言设置默认引擎
if vim.g.translator_target_lang and vim.g.translator_target_lang:match("zh") then
	vim.g.translator_default_engines = vim.g.translator_default_engines
		or {
			"bing",
			"google",
			"haici",
			"youdao",
		}
else
	vim.g.translator_default_engines = vim.g.translator_default_engines or { "google" }
end

-- 翻译状态
vim.g.translator_status = ""

-- ==================================================
-- 快捷键映射
-- ==================================================

-- 普通模式映射
vim.api.nvim_set_keymap("n", "<Plug>Translate", ":Translate<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("n", "<Plug>TranslateW", ":TranslateW<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("n", "<Plug>TranslateR", "viw:<C-u>TranslateR<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("n", "<Plug>TranslateX", ":TranslateX<CR>", { silent = true, noremap = true })

-- 可视模式映射
vim.api.nvim_set_keymap("v", "<Plug>TranslateV", ":Translate<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("v", "<Plug>TranslateWV", ":TranslateW<CR>", { silent = true, noremap = true })
vim.api.nvim_set_keymap("v", "<Plug>TranslateRV", ":TranslateR<CR>", { silent = true, noremap = true })

-- ==================================================
-- 用户命令
-- ==================================================

-- 翻译并在命令行显示
vim.api.nvim_create_user_command("Translate", function(opts)
	require("translator").start("echo", opts.bang, opts.range, opts.line1, opts.line2, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
	complete = function(arg_lead, cmd_line, cursor_pos)
		return require("translator.cmdline").complete(arg_lead, cmd_line, cursor_pos)
	end,
})

-- 翻译并在窗口显示
vim.api.nvim_create_user_command("TranslateW", function(opts)
	require("translator").start("window", opts.bang, opts.range, opts.line1, opts.line2, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
	complete = function(arg_lead, cmd_line, cursor_pos)
		return require("translator.cmdline").complete(arg_lead, cmd_line, cursor_pos)
	end,
})

-- 翻译并替换选中文本
vim.api.nvim_create_user_command("TranslateR", function(opts)
	require("translator").start("replace", opts.bang, opts.range, opts.line1, opts.line2, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
	complete = function(arg_lead, cmd_line, cursor_pos)
		return require("translator.cmdline").complete(arg_lead, cmd_line, cursor_pos)
	end,
})

-- 翻译剪贴板内容
vim.api.nvim_create_user_command("TranslateX", function(opts)
	-- 获取剪贴板内容并附加到参数
	local clipboard = vim.fn.getreg("*")
	local args = opts.args
	if args ~= "" then
		args = args .. " " .. clipboard
	else
		args = clipboard
	end
	require("translator").start("echo", opts.bang, opts.range, opts.line1, opts.line2, args)
end, {
	nargs = "*",
	bang = true,
	range = true,
	complete = function(arg_lead, cmd_line, cursor_pos)
		return require("translator.cmdline").complete(arg_lead, cmd_line, cursor_pos)
	end,
})

-- 导出历史记录
vim.api.nvim_create_user_command("TranslateH", function()
	require("translator.history").export()
end, {
	nargs = 0,
})

-- 打开日志
vim.api.nvim_create_user_command("TranslateL", function()
	require("translator.logger").open_log()
end, {
	nargs = 0,
})
