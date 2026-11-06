dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup()
vim.cmd(":Translate hello")
vim.wait(8000, function()
	return vim.g.translator_status == ""
end)
local win_open = H.floats()
H.report("S7 success", {
	{ "window-open", win_open == 1, win_open },
	{ "esc-closes-window", H.map() ~= "", H.map() },
	{ "no-error", #H.msgs == 0, H.msgs },
})
H.esc()
H.wait(300)
H.report("S7 after esc", {
	{ "window-closed", H.floats() == 0, H.floats() },
	{ "key-restored", H.map() == "", H.map() },
})
vim.cmd("qa!")
