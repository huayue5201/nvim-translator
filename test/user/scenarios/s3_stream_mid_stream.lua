dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup()
vim.cmd(":Translate hello")
H.wait(1600) -- first engine arrived -> window open, others still pending
local open = H.floats()
local inflight = vim.g.translator_status
H.esc()
H.wait(400)
H.settle()
H.report("S3 streaming esc mid-stream", {
	{ "window-opened", open == 1, open },
	{ "still-translating", inflight == "translating", inflight },
	{ "window-closed", H.floats() == 0, H.floats() },
	{ "proc-killed", H.procs() == 0, H.procs() },
	{ "status", vim.g.translator_status == "", vim.g.translator_status },
	{ "key-restored", H.map() == "", H.map() },
})
H.wait(3000)
H.report("S3 late", { { "stays-closed", H.floats() == 0, H.floats() } })
vim.cmd("qa!")
