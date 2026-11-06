dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup() -- streaming
vim.cmd(":Translate hello")
H.wait(500)
local map_during = H.map() ~= ""
H.esc()
H.wait(400)
H.report("S2 streaming esc before first result", {
	{ "cancel-key-installed", map_during, map_during },
	{ "proc-killed", H.procs() == 0, H.procs() },
	{ "no-window", H.floats() == 0, H.floats() },
	{ "key-restored", H.map() == "", H.map() },
	{ "no-error", #H.msgs == 0, H.msgs },
})
H.wait(4000)
H.report("S2 late", {
	{ "still-no-window", H.floats() == 0, H.floats() },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
})
vim.cmd("qa!")
