-- FileName: translator.lua
-- FilePath: after/syntax/translator.lua
-- Description: Syntax highlighting for translator buffer

if vim.b.current_syntax then
	return
end

vim.cmd([[
    syntax match TranslatorQuery /\v⟦.*⟧/
    syntax match TranslatorDelimiter /\v\─.*\─/

    hi def link TranslatorQuery Identifier
    hi def link TranslatorDelimiter Comment

    hi def link Translator Normal
    hi def link TranslatorBorder NormalFloat
]])

vim.b.current_syntax = "translator"
