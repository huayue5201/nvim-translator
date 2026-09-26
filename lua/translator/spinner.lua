-- File: lua/translator/spinner.lua
-- Cursor-following spinner shown while a translation request is in flight.
-- Lightweight single-spinner port of https://github.com/xieyonn/spinner.nvim.

local M = {}

local DEFAULT_FRAMES = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local state = {
	win = nil,
	buf = nil,
	timer = nil,
	frame = 0,
	frames = nil,
}

local function win_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function close()
	if state.timer then
		pcall(vim.fn.timer_stop, state.timer)
		state.timer = nil
	end
	if win_valid(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	state.win = nil
	state.buf = nil
	state.frame = 0
	state.frames = nil
end

local function tick()
	if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
		return
	end
	local frames = state.frames
	if not frames or #frames == 0 then
		return
	end

	state.frame = state.frame % #frames + 1
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { frames[state.frame] })
end

function M.start()
	close()

	local frames = vim.g.translator_spinner_frames or DEFAULT_FRAMES
	if type(frames) ~= "table" or #frames == 0 then
		return
	end
	state.frames = frames

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { frames[1] })

	local ok, win = pcall(vim.api.nvim_open_win, state.buf, false, {
		relative = "cursor",
		row = -1,
		col = 1,
		width = 1,
		height = 1,
		style = "minimal",
		border = "none",
		focusable = false,
		zindex = 50,
	})
	if not ok then
		-- 光标贴近屏幕边缘时浮窗可能创建失败；静默降级，不影响翻译。
		state.buf = nil
		state.frames = nil
		return
	end
	state.win = win

	vim.api.nvim_set_hl(0, "TranslatorSpinner", { link = "Special" })
	vim.api.nvim_win_set_option(state.win, "winhl", "Normal:TranslatorSpinner")
	pcall(vim.api.nvim_win_set_option, state.win, "winblend", 60)

	state.frame = 1
	local interval = vim.g.translator_spinner_interval or 80
	state.timer = vim.fn.timer_start(interval, tick, { ["repeat"] = -1 })
end

M.close = close

return M
