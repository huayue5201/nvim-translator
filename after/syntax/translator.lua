-- 可选：使用 Neovim API 设置高亮
local function setup_highlights()
	-- 清除已有的高亮
	vim.cmd("highlight clear TranslatorQuery")
	vim.cmd("highlight clear TranslatorDelimiter")
	vim.cmd("highlight clear TranslatorTarget")

	-- 使用 API 设置（Neovim 0.7+）
	vim.api.nvim_set_hl(0, "TranslatorQuery", { link = "Identifier" })
	vim.api.nvim_set_hl(0, "TranslatorDelimiter", { link = "Comment" })
	vim.api.nvim_set_hl(0, "TranslatorTarget", { link = "Keyword" })
end

if vim.b.current_syntax then
	return
end

vim.cmd([[
    syntax match TranslatorQuery /\v⟦.*⟧/
    syntax match TranslatorDelimiter /\v\─.*\─/
    syntax match TranslatorTarget /^\s*↳/
]])

setup_highlights()

vim.b.current_syntax = "translator"
