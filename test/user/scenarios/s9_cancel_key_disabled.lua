dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false, cancel_key = false })
vim.cmd(":Translate hello")
H.wait(500)
local map_during = H.map()
vim.wait(4000, function()
	return vim.g.translator_status == ""
end)
H.report("S9 cancel_key=false", {
	{ "no-map", map_during == "", map_during },
	{ "still-completes", vim.g.translator_status == "", vim.g.translator_status },
	{ "window-open", H.floats() == 1, H.floats() },
	{ "no-esc-map", H.map() == "", H.map() },
})
vim.cmd("qa!")
