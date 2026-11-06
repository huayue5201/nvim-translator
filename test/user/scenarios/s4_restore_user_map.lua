dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
for _, variant in ipairs({ "string", "lua" }) do
	H.msgs = {}
	H.setup({ incremental = false })
	if variant == "string" then
		vim.keymap.set("n", "<Esc>", "<cmd>let g:mine=1<cr>", { silent = true })
	else
		vim.keymap.set("n", "<Esc>", function()
			vim.g.mine = 1
		end, { silent = true, desc = "mine" })
	end
	local before = vim.fn.maparg("<Esc>", "n", false, true)
	vim.cmd(":Translate hello")
	H.wait(400)
	H.esc()
	H.wait(400)
	local after = vim.fn.maparg("<Esc>", "n", false, true)
	H.esc()
	H.wait(100)
	H.report("S4 restore " .. variant, {
		{ "mine-ran-after", vim.g.mine == 1, vim.g.mine },
		{ "callback-kept", (before.callback ~= nil) == (after.callback ~= nil), after.callback },
		{ "rhs-kept", before.rhs == after.rhs, { before.rhs, after.rhs } },
		{ "desc-kept", before.desc == after.desc, { before.desc, after.desc } },
	})
	vim.g.mine = nil
	vim.keymap.del("n", "<Esc>")
end
H.report("S4 no-leak", { { "map-gone", H.map() == "", H.map() } })
vim.cmd("qa!")
