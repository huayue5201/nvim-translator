dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup()
vim.cmd(":Translate hello")
H.wait(400)
H.esc()
H.esc()
H.esc()
H.wait(400)
H.report("S10 triple esc", {
	{ "no-error", #H.msgs == 0, H.msgs },
	{ "proc", H.procs() == 0, H.procs() },
	{ "floats", H.floats() == 0, H.floats() },
	{ "map", H.map() == "", H.map() },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
})
-- normal editing Esc still works afterwards
vim.cmd("startinsert")
H.wait(100)
H.esc()
H.wait(100)
H.report(
	"S10 esc-in-insert-leaves-insert",
	{ { "mode", vim.api.nvim_get_mode().mode == "n", vim.api.nvim_get_mode().mode } }
)
vim.cmd("qa!")
