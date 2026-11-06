dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false })
vim.cmd(":Translate hello")
H.wait(500)
local during = { vim.g.translator_status, H.procs(), H.floats(), H.map() ~= "" }
H.esc()
H.wait(500)
H.settle()
H.report("S1 buffered esc", {
	{ "status-during=translating", during[1] == "translating", during[1] },
	{ "proc-during", during[2] == 1, during[2] },
	{ "spinner-shown", during[3] == 1, during[3] },
	{ "cancel-key-installed", during[4] == true, during[4] },
	{ "status-cleared", vim.g.translator_status == "", vim.g.translator_status },
	{ "proc-killed", H.procs() == 0, H.procs() },
	{ "floats-closed", H.floats() == 0, H.floats() },
	{ "key-restored", H.map() == "", H.map() },
	{ "no-error", #H.msgs == 0, H.msgs },
})
H.wait(3500)
H.report("S1 late (no result window)", {
	{ "no-window", H.floats() == 0, H.floats() },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
})
vim.cmd("qa!")
