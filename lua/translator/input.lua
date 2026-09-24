-- lua/translator/input.lua
-- Interactive input: prompt for text (prefilled with the current context),
-- then run it through the normal translation pipeline.

local cmdline = require("translator.cmdline")
local util = require("translator.util")

local M = {}

--- Prefill the input box with the text the normal command would translate
--- (visual selection -> line range -> word under cursor).
local function default_text(opts)
	opts = opts or { range = 0, line1 = 1, line2 = 1 }
	return util.text_proc(util.get_text_from_context(opts))
end

--- Open an input prompt and translate whatever the user types.
--- @param opts table command options ({ bang, range, line1, line2, args })
function M.prompt(opts)
	opts = opts or { bang = false, range = 0, line1 = 1, line2 = 1, args = "" }

	local default = default_text(opts)

	local input_opts = { prompt = "Translate: " }
	if default ~= "" then
		input_opts.default = default
	end

	vim.ui.input(input_opts, function(input)
		if not input or vim.trim(input) == "" then
			return
		end

		-- Reuse the normal parser so --flags and ! all work here too.
		local options = cmdline.parse({
			args = input,
			bang = opts.bang,
			range = 0,
			line1 = 1,
			line2 = 1,
		})
		if not options then
			return
		end

		-- Interactive floating window (fixed position, focusable, copyable).
		require("translator").translate(options, "interactive")
	end)
end

return M
