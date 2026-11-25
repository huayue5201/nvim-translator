dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
-- The peek is already visible when its source window closes: it must follow
-- the source window down instead of staying on screen orphaned.
H.setup() -- incremental streaming on

local function peek_wins()
	local wins = {}
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = vim.api.nvim_get_option_value("filetype", { buf = buf })
		if ft == "translator" then
			wins[#wins + 1] = win
		end
	end
	return wins
end

local src_buf = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(src_buf, 0, -1, false, { "hello world" })
local src_win = vim.api.nvim_open_win(src_buf, true, {
	relative = "editor",
	row = 2,
	col = 2,
	width = 20,
	height = 3,
	style = "minimal",
})
vim.api.nvim_win_set_cursor(src_win, { 1, 0 })

vim.cmd(":Translate hello")
local opened = vim.wait(8000, function()
	return #peek_wins() > 0
end, 20)
local before = #peek_wins()

vim.api.nvim_win_close(src_win, true)
local closed = vim.wait(3000, function()
	return #peek_wins() == 0
end, 20)
H.settle()

H.report("S14 source closed with peek", {
	{ "peek-opened", opened and before == 1, before },
	{ "peek-closed", closed and #peek_wins() == 0, #peek_wins() },
	{ "no-error", #H.msgs == 0, H.msgs },
})
vim.cmd("qa!")
