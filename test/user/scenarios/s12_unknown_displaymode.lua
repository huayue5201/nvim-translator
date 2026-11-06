dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "hello world" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })

-- Removed display modes (e.g. "echo", used by older user configs) must fall
-- back to the floating window, never to in-buffer replacement.
require("translator").start("echo", { bang = false, range = 0, line1 = 1, line2 = 1, args = "hello" })
vim.wait(6000, function()
	return H.floats() > 0
end)
H.report("S12 unknown display mode", {
	{ "window-opened", H.floats() == 1, H.floats() },
	{
		"buffer-untouched",
		vim.api.nvim_buf_get_lines(buf, 0, -1, false)[1] == "hello world",
		vim.api.nvim_buf_get_lines(buf, 0, -1, false),
	},
})
vim.cmd("qa!")
