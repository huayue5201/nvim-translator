dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
-- The window that started the translation closes before the result arrives:
-- no peek should be resurrected, and nothing should error.
H.setup({ incremental = false })

local src_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, { "hello world" })
local src_win = vim.api.nvim_open_win(src_buf, true, {
	relative = "editor",
	row = 2,
	col = 2,
	width = 20,
	height = 3,
	style = "minimal",
})
vim.api.nvim_win_set_cursor(src_win, { 1, 0 })

vim.cmd(":Translate hello")
H.wait(200) -- request in flight (SLOW_DELAY=1)
vim.api.nvim_win_close(src_win, true)
H.wait(2500) -- result arrives after the source is gone
H.settle()

H.report("S13 source closed before result", {
	{ "floats-closed", H.floats() == 0, H.floats() },
	{ "no-error", #H.msgs == 0, H.msgs },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
})
vim.cmd("qa!")
