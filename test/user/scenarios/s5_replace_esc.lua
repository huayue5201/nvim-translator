dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false })
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "hello world" })
require("translator").start("replace", { args = "", range = 1 })
H.wait(400)
H.esc()
H.wait(400)
H.report("S5 replace esc", {
	{
		"buffer-untouched",
		vim.api.nvim_buf_get_lines(0, 0, -1, false)[1] == "hello world",
		vim.api.nvim_buf_get_lines(0, 0, -1, false)[1],
	},
	{ "proc-killed", H.procs() == 0, H.procs() },
	{ "key-restored", H.map() == "", H.map() },
})
vim.cmd("qa!")
