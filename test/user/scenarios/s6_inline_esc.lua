dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false })
local buf = vim.api.nvim_get_current_buf()
vim.bo[buf].filetype = "lua"
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "-- 注释一", "local x = 1", "-- 注释二", "-- 注释三" })
vim.cmd(":TranslateV")
H.wait(500)
local map_during = H.map() ~= ""
H.esc()
H.wait(400)
local ns = vim.api.nvim_create_namespace("translator_inline")
H.report("S6 inline esc", {
	{ "cancel-key-installed", map_during, map_during },
	{ "proc-killed", H.procs() == 0, H.procs() },
	{
		"no-lines-rendered",
		#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 0,
		#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}),
	},
	{ "session-kept", require("translator.inline").active(buf), require("translator.inline").active(buf) },
	{ "key-restored", H.map() == "", H.map() },
})
-- re-translate must still work
vim.cmd(":TranslateV") -- toggle off
H.report(
	"S6 toggle-off-ok",
	{ { "inactive", not require("translator.inline").active(buf), require("translator.inline").active(buf) } }
)
vim.cmd(":TranslateV")
vim.wait(15000, function()
	return #vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) >= 3
end)
H.report("S6 works-after-cancel", {
	{
		"lines-rendered",
		#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}) == 3,
		#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}),
	},
	{ "key-restored-2", H.map() == "", H.map() },
})
vim.cmd("qa!")
