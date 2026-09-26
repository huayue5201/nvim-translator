-- File: lua/translator/window/float.lua
-- Floating window with double border.
-- Two modes:
--   * create()             cursor-following, non-focusable (translation peek)
--                          with secondary-action key hints (speak / Anki / copy)
--   * create_interactive() fixed position, focusable (copy text from result)

local buffer = require("translator.buffer")
local util = require("translator.util")
local state = require("translator.state")
local tts = require("translator.tts")
local anki = require("translator.anki")

local M = {}

local state_win = {
	win = nil,
	aug = "translator_float_close",
}

local function win_valid(win)
	return win and vim.api.nvim_win_is_valid(win)
end

-- Forward declaration: secondary actions install_maps/add_anki refer to it.
local close

---------------------------------------------------------------------
-- Secondary actions (operate on the last translation)
---------------------------------------------------------------------
local function speak_source()
	local s = state.get()
	if s and s.trans and s.trans.text and s.trans.text ~= "" then
		tts.speak(s.trans.text, s.options.source_lang)
	end
end

local function speak_target()
	local s = state.get()
	local p = state.paraphrase()
	if p ~= "" and s then
		tts.speak(p, s.options.target_lang)
	end
end

local function add_anki()
	close()
	anki.add()
end

local function copy_paraphrase()
	local p = state.paraphrase()
	if p ~= "" then
		vim.fn.setreg("+", p)
		vim.fn.setreg('"', p)
		util.show_msg("已复制译文：" .. p)
	end
end

---------------------------------------------------------------------
-- Temporary keymaps (active only while the peek window is open).
-- Original mappings are saved and restored on close, so they do not
-- clobber other plugins (e.g. flash.nvim's "s").
---------------------------------------------------------------------
local active_maps = {}
local saved_maps = {}

local function find_global_map(mode, lhs)
	for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
		if m.lhs == lhs and m.buffer == 0 then
			return m
		end
	end
	return nil
end

local function restore_map(mode, lhs, m)
	local opts = {
		expr = m.expr == 1,
		nowait = m.nowait == 1,
		silent = m.silent == 1,
		script = m.script == 1,
		desc = m.desc,
	}
	if m.noremap == 1 then
		opts.noremap = true
	else
		opts.remap = true
	end
	if m.callback then
		vim.keymap.set(mode, lhs, m.callback, opts)
	elseif m.rhs then
		vim.keymap.set(mode, lhs, m.rhs, opts)
	end
end

local function clear_maps()
	for _, m in ipairs(active_maps) do
		pcall(vim.keymap.del, m.mode, m.lhs)
		local key = m.mode .. ":" .. m.lhs
		local saved = saved_maps[key]
		if saved then
			pcall(restore_map, m.mode, m.lhs, saved)
			saved_maps[key] = nil
		end
	end
	active_maps = {}
end

local function install_maps()
	clear_maps()
	local maps = {
		{ "n", "s", speak_source },
		{ "n", "S", speak_target },
		{ "n", "a", add_anki },
		{ "n", "y", copy_paraphrase },
		{ "n", "<Esc>", close },
		-- 可视模式翻译后浮窗弹出，光标仍处可视模式；让 <Esc> 优先关闭浮窗
		-- 而不是先退出选择，避免用户需要按两下 Esc。
		-- 注：'v' 模式映射覆盖 v / V / Ctrl-V 全部可视模式，无需单独注册 'x'。
		{ "v", "<Esc>", close },
	}
	for _, m in ipairs(maps) do
		saved_maps[m[1] .. ":" .. m[2]] = find_global_map(m[1], m[2])
		vim.keymap.set(m[1], m[2], m[3], { silent = true })
		table.insert(active_maps, { mode = m[1], lhs = m[2] })
	end
end

---------------------------------------------------------------------
-- Key hint shown in the window border footer
---------------------------------------------------------------------
local function footer()
	return {
		{ "s", "Special" }, { " 原文  ", "FloatFooter" },
		{ "S", "Special" }, { " 译文  ", "FloatFooter" },
		{ "a", "Special" }, { " Anki  ", "FloatFooter" },
		{ "y", "Special" }, { " 复制  ", "FloatFooter" },
		{ "Esc", "Special" }, { " 关闭", "FloatFooter" },
	}
end

close = function()
	if win_valid(state_win.win) then
		pcall(vim.api.nvim_win_close, state_win.win, true)
	end
	state_win.win = nil
	clear_maps()
	pcall(vim.api.nvim_del_augroup_by_name, state_win.aug)
	state_win.aug = "translator_float_close"
end

---------------------------------------------------------------------
-- Shared rendering + window opening
---------------------------------------------------------------------
local function build(lines, cfg, enter, win_cfg)
	close()

	-- 对内容进行居中排版
	lines = util.fit_lines(lines, cfg.width)

	-- 创建 buffer
	local bufnr = buffer.create_scratch_buf(lines)

	-- 单层浮窗，使用 double border
	state_win.win = vim.api.nvim_open_win(bufnr, enter, vim.tbl_extend("force", {
		width = cfg.width,
		height = cfg.height,
		style = "minimal",
		border = "rounded",
		zindex = 100,
	}, win_cfg))
	vim.api.nvim_win_set_option(state_win.win, "winhl", "Normal:Translator")

	-- 可选：设置浮窗永远不被其他窗口覆盖（需要 Neovim 0.9+）
	pcall(vim.api.nvim_win_set_config, state_win.win, {
		zindex = 100,
	})

	return state_win.win, bufnr
end

function M.has_scroll()
	return win_valid(state_win.win)
end

function M.scroll(forward, amount)
	if not M.has_scroll() then
		return "<Ignore>"
	end
	amount = amount or 1
	vim.api.nvim_win_call(state_win.win, function()
		local key = forward and "<C-e>" or "<C-y>"
		for _ = 1, amount do
			vim.cmd("normal! " .. key)
		end
	end)
	return "<Ignore>"
end

---------------------------------------------------------------------
-- Default: cursor-following peek window (non-focusable, auto-close)
---------------------------------------------------------------------
function M.create(lines, cfg)
	state_win.aug = "translator_float_close"
	local win = build(lines, cfg, false, {
		relative = "cursor",
		row = cfg.row,
		col = cfg.col,
		focusable = false,
		footer = footer(),
		footer_pos = "center",
	})

	install_maps()

	local aug = vim.api.nvim_create_augroup(state_win.aug, { clear = true })
	vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
		group = aug,
		buffer = 0,
		callback = function()
			vim.defer_fn(close, 10)
		end,
	})

	return win
end

---------------------------------------------------------------------
-- Interactive: fixed position, focusable, cursor enters the window so
-- the user can select and copy text. `q` / `<Esc>` / leaving closes it.
---------------------------------------------------------------------
function M.create_interactive(lines, cfg)
	state_win.aug = "translator_interactive_close"
	local win, bufnr = build(lines, cfg, true, {
		relative = "editor",
		row = cfg.row,
		col = cfg.col,
		focusable = true,
	})

	local map_opts = { buffer = bufnr, silent = true, nowait = true }
	vim.keymap.set("n", "q", close, map_opts)
	vim.keymap.set("n", "<Esc>", close, map_opts)

	local aug = vim.api.nvim_create_augroup(state_win.aug, { clear = true })
	vim.api.nvim_create_autocmd("WinLeave", {
		group = aug,
		pattern = tostring(win),
		callback = function()
			vim.defer_fn(close, 10)
		end,
	})

	return win
end

M.close = close
return M
