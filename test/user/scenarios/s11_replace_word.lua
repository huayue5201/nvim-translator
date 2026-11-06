dofile(vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/../harness.lua")
H.setup({ incremental = false })
local buf = vim.api.nvim_get_current_buf()
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha beta gamma" })
vim.api.nvim_win_set_cursor(0, { 1, 6 }) -- on "beta"
vim.cmd(":TranslateR")
vim.wait(6000, function()
	return vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "alpha T:beta gamma"
end)
H.report("S11 :TranslateR without selection replaces word under cursor", {
	{
		"word-replaced",
		vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "alpha T:beta gamma",
		vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1],
	},
	{ "no-warning", #H.msgs == 0, H.msgs },
	{ "cursor-kept", vim.api.nvim_win_get_cursor(0)[1] == 1, vim.api.nvim_win_get_cursor(0) },
})

-- no word under cursor: warning, nothing replaced
H.msgs = {}
vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- on the space between "alpha" and "beta"
vim.cmd(":TranslateR")
H.wait(3000)
H.report("S11 no word under cursor", {
	{
		"buffer-untouched",
		vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "alpha T:beta gamma",
		vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1],
	},
	{ "warned", #H.msgs == 1 and H.msgs[1]:find("No word under cursor", 1, true) ~= nil, H.msgs },
})

-- explicit line range replaces the whole line
H.msgs = {}
vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "one", "two words", "three" })
vim.cmd(":2TranslateR")
vim.wait(6000, function()
	return vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "T:two words"
end)
H.report("S11 line range", {
	{
		"line-replaced",
		vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1] == "T:two words",
		vim.api.nvim_buf_get_lines(buf, 0, -1, false),
	},
	{
		"others-kept",
		vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == "one"
			and vim.api.nvim_buf_get_lines(buf, 2, 3, false)[1] == "three",
		vim.api.nvim_buf_get_lines(buf, 0, -1, false),
	},
})
vim.cmd("qa!")
