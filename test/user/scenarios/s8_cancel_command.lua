dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup()
vim.cmd(":Translate hello")
H.wait(500)
vim.cmd(":TranslateCancel")
H.wait(300)
H.report("S8 :TranslateCancel", {
	{ "proc-killed", H.procs() == 0, H.procs() },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
	{ "no-window", H.floats() == 0, H.floats() },
	{ "key-restored", H.map() == "", H.map() },
})
vim.cmd(":TranslateCancel") -- no-op when idle
H.report("S8 idle cancel noop", { { "no-error", #H.msgs == 0, H.msgs }, { "map", H.map() == "", H.map() } })
vim.cmd("qa!")
