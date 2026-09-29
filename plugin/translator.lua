-- File: plugin/translator.lua
-- Description: Main plugin file for translator.nvim (Neovim-native)

if vim.g.loaded_translator then
	return
end
vim.g.loaded_translator = 1

---------------------------------------------------------------------
-- 配置通过 require("translator").setup(opts) 提供
-- （见 lua/translator/config.lua），不再使用 vim.g.translator_* 全局变量。
---------------------------------------------------------------------

---------------------------------------------------------------------
-- Highlights (restrained: dim source/phonetic, accent engine header)
---------------------------------------------------------------------
require("translator.highlight").setup()

---------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------
local function run_translate(displaymode, opts)
	require("translator").start(displaymode, opts)
end

vim.api.nvim_create_user_command("Translate", function(opts)
	run_translate("echo", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateW", function(opts)
	run_translate("window", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateR", function(opts)
	run_translate("replace", opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateX", function(opts)
	local clipboard = vim.fn.getreg("*")
	local args = vim.trim((opts.args or "") .. " " .. clipboard)
	require("translator").start("echo", {
		bang = opts.bang,
		range = 0,
		line1 = 1,
		line2 = 1,
		args = args,
	})
end, { nargs = "*", bang = true })

vim.api.nvim_create_user_command("TranslateI", function(opts)
	require("translator.input").prompt(opts)
end, { nargs = "*", bang = true, range = true })

vim.api.nvim_create_user_command("TranslateH", function()
	require("translator.history").export()
end, {})

vim.api.nvim_create_user_command("TranslateL", function()
	require("translator.logger").open_log()
end, {})

vim.api.nvim_create_user_command("TranslateCacheClear", function()
	require("translator.cache").clear()
	vim.notify("Translator cache cleared", vim.log.levels.INFO)
end, {})

vim.api.nvim_create_user_command("TranslateSay", function(opts)
	require("translator.tts").say(opts.bang, opts)
end, { bang = true, range = true })

vim.api.nvim_create_user_command("TranslateA", function()
	require("translator.anki").add()
end, {})

vim.api.nvim_create_user_command("TranslateApi", function(opts)
	require("translator").translate_api({
		range = opts.range,
		line1 = opts.line1,
		line2 = opts.line2,
		args = opts.args,
	})
end, { nargs = "*", range = true })
