-- FileName: translator.lua
-- FilePath: plugin/translator.lua
-- Description: Main plugin file for translator.nvim (Neovim-native)

if vim.g.loaded_translator then
	return
end
vim.g.loaded_translator = 1

---------------------------------------------------------------------
-- Default settings
---------------------------------------------------------------------
vim.g.translator_history_enable = vim.g.translator_history_enable or false
vim.g.translator_proxy_url = vim.g.translator_proxy_url or ""
vim.g.translator_source_lang = vim.g.translator_source_lang or "auto"
vim.g.translator_target_lang = vim.g.translator_target_lang or "zh"
vim.g.translator_translate_shell_options = vim.g.translator_translate_shell_options or {}

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

vim.g.translator_window_max_height = vim.g.translator_window_max_height or 999
vim.g.translator_window_max_width = vim.g.translator_window_max_width or 999
vim.g.translator_window_type = vim.g.translator_window_type or "popup"

if vim.g.translator_target_lang:match("zh") then
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

vim.g.translator_status = ""

---------------------------------------------------------------------
-- Keymaps
---------------------------------------------------------------------
vim.keymap.set("n", "<Plug>Translate", "<cmd>Translate<CR>", { silent = true })
vim.keymap.set("n", "<Plug>TranslateW", "<cmd>TranslateW<CR>", { silent = true })
vim.keymap.set("n", "<Plug>TranslateR", "viw:<C-u>TranslateR<CR>", { silent = true })
vim.keymap.set("n", "<Plug>TranslateX", "<cmd>TranslateX<CR>", { silent = true })

vim.keymap.set("v", "<Plug>TranslateV", "<cmd>Translate<CR>", { silent = true })
vim.keymap.set("v", "<Plug>TranslateWV", "<cmd>TranslateW<CR>", { silent = true })
vim.keymap.set("v", "<Plug>TranslateRV", "<cmd>TranslateR<CR>", { silent = true })

---------------------------------------------------------------------
-- Helper: detect visual mode
---------------------------------------------------------------------
local function get_text_from_context(opts)
	local util = require("translator.util")

	if vim.fn.mode():match("[vV\22]") then
		-- Visual mode: always use Neovim-native selection
		return util.get_visual_selection()
	end

	-- Normal mode
	if opts.range == 0 then
		return vim.fn.expand("<cword>")
	elseif opts.range == 1 then
		return vim.api.nvim_get_current_line()
	else
		local lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
		return table.concat(lines, "\n")
	end
end

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------
vim.api.nvim_create_user_command("Translate", function(opts)
	local text = get_text_from_context(opts)
	require("translator").start("echo", opts.bang, text, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
})

vim.api.nvim_create_user_command("TranslateW", function(opts)
	local text = get_text_from_context(opts)
	require("translator").start("window", opts.bang, text, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
})

vim.api.nvim_create_user_command("TranslateR", function(opts)
	local text = get_text_from_context(opts)
	require("translator").start("replace", opts.bang, text, opts.args)
end, {
	nargs = "*",
	bang = true,
	range = true,
})

vim.api.nvim_create_user_command("TranslateX", function(opts)
	local clipboard = vim.fn.getreg("*")
	local args = opts.args ~= "" and (opts.args .. " " .. clipboard) or clipboard
	require("translator").start("echo", opts.bang, clipboard, args)
end, {
	nargs = "*",
	bang = true,
})

vim.api.nvim_create_user_command("TranslateH", function()
	require("translator.history").export()
end, {})

vim.api.nvim_create_user_command("TranslateL", function()
	require("translator.logger").open_log()
end, {})
