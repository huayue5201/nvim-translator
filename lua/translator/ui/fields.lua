-- File: lua/translator/ui/fields.lua
-- Multi-field input popup: one input window per field, arranged in a parent
-- floating window. Used by the Anki feature to edit note fields before saving.
--
-- Keys:
--   <Tab> / <S-Tab>   switch focus between fields
--   <Up> / <Down>     browse history for the current field (insert mode)
--   <CR>              submit (normal mode)
--   q / <Esc>         cancel (normal mode)

local M = {}

-- Border highlights (default = true so users can override them).
vim.api.nvim_set_hl(0, "TranslatorInputActive", { fg = "#5FAFFF", default = true })
vim.api.nvim_set_hl(0, "TranslatorInputInactive", { fg = "#666666", default = true })

local MAX_HEIGHT = 8

-- In-memory history per field key.
local history_db = {}

local function get_history(field_key)
	if not history_db[field_key] then
		history_db[field_key] = {}
	end
	return history_db[field_key]
end

local function add_to_history(field_key, value)
	if value == nil or value == "" then
		return
	end
	local history = get_history(field_key)
	for i, v in ipairs(history) do
		if v == value then
			table.remove(history, i)
			break
		end
	end
	table.insert(history, 1, value)
	while #history > 100 do
		table.remove(history)
	end
end

---------------------------------------------------------------------
-- One input window per field
---------------------------------------------------------------------
local function create_input_window(parent, title, width)
	local buf = vim.api.nvim_create_buf(false, true)

	local win = vim.api.nvim_open_win(buf, true, {
		relative = "win",
		win = parent,
		row = 1,
		col = 2,
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
		title = " " .. title .. " ",
		title_pos = "center",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "" })

	return { buf = buf, win = win }
end

local function get_value(buf)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	return table.concat(lines, "\n")
end

function M.open(opts)
	opts = opts or {}
	local fields = opts.fields or error("fields is required")
	local on_submit = opts.on_submit

	local prev_mode = vim.fn.mode()
	local width = opts.width or 50
	local is_closing = false

	local history_index = {}
	local temp_input = {}

	-------------------------------------------------------------------
	-- Parent floating window (follows cursor)
	-------------------------------------------------------------------
	local parent_buf = vim.api.nvim_create_buf(false, true)
	local parent = vim.api.nvim_open_win(parent_buf, false, {
		relative = "cursor",
		row = 1,
		col = 1,
		width = width + 6,
		height = 12,
		style = "minimal",
		border = "rounded",
	})

	-------------------------------------------------------------------
	-- Create one input window per field, prefilled with its default value
	-------------------------------------------------------------------
	local windows = {}
	for i, field in ipairs(fields) do
		windows[i] = create_input_window(parent, field.label, width)

		local value = field.value or ""
		if value ~= "" then
			vim.api.nvim_buf_set_lines(windows[i].buf, 0, -1, false, vim.split(value, "\n"))
		end

		history_index[field.key] = 0
		temp_input[field.key] = value
	end

	local current_focus_index = 1

	-------------------------------------------------------------------
	-- Highlight the focused field's border
	-------------------------------------------------------------------
	local function update_borders()
		for i, w in ipairs(windows) do
			local hl = (i == current_focus_index) and "TranslatorInputActive" or "TranslatorInputInactive"
			vim.api.nvim_win_set_config(w.win, {
				border = {
					{ "╭", hl },
					{ "─", hl },
					{ "╮", hl },
					{ "│", hl },
					{ "╯", hl },
					{ "─", hl },
					{ "╰", hl },
					{ "│", hl },
				},
			})
		end
	end

	-------------------------------------------------------------------
	-- Auto-grow the field window with its content
	-------------------------------------------------------------------
	local function resize_window(win_obj)
		local lines = vim.api.nvim_buf_get_lines(win_obj.buf, 0, -1, false)
		local height = math.min(math.max(#lines, 1), MAX_HEIGHT)
		vim.api.nvim_win_set_height(win_obj.win, height)
	end

	-------------------------------------------------------------------
	-- Stack the field windows inside the parent window
	-------------------------------------------------------------------
	local function relayout()
		local y = 1
		for _, w in ipairs(windows) do
			vim.api.nvim_win_set_config(w.win, {
				relative = "win",
				win = parent,
				row = y,
				col = 2,
			})
			y = y + vim.api.nvim_win_get_height(w.win) + 2
		end
		vim.api.nvim_win_set_height(parent, y + 1)
	end

	local function save_current_input()
		local field = fields[current_focus_index]
		if field then
			temp_input[field.key] = get_value(windows[current_focus_index].buf)
		end
	end

	-------------------------------------------------------------------
	-- History navigation for the current field
	-------------------------------------------------------------------
	local function navigate_history(direction)
		if is_closing then
			return
		end

		local field = fields[current_focus_index]
		if not field then
			return
		end

		local field_key = field.key
		local history = get_history(field_key)
		if #history == 0 then
			return
		end

		if history_index[field_key] == 0 then
			save_current_input()
		end

		local new_index = history_index[field_key] + direction
		if new_index < 0 then
			new_index = 0
		elseif new_index > #history then
			new_index = #history
		end

		local buf = windows[current_focus_index].buf
		if new_index == 0 then
			local text = temp_input[field_key]
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, text ~= "" and { text } or { "" })
		else
			vim.api.nvim_buf_set_lines(buf, 0, -1, false, { history[new_index] })
		end

		history_index[field_key] = new_index

		vim.schedule(function()
			local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
			local line_len = lines[1] and #lines[1] or 0
			pcall(vim.api.nvim_win_set_cursor, windows[current_focus_index].win, { 1, line_len })
		end)

		resize_window(windows[current_focus_index])
		relayout()
	end

	-------------------------------------------------------------------
	-- Close all windows (idempotent)
	-------------------------------------------------------------------
	local function close_all()
		if is_closing then
			return
		end
		is_closing = true

		vim.schedule(function()
			for _, w in ipairs(windows) do
				if w.win and vim.api.nvim_win_is_valid(w.win) then
					pcall(vim.api.nvim_win_close, w.win, true)
				end
			end
			if parent and vim.api.nvim_win_is_valid(parent) then
				pcall(vim.api.nvim_win_close, parent, true)
			end

			if prev_mode == "i" then
				pcall(vim.cmd, "startinsert")
			end

			is_closing = false
		end)
	end

	local function focus(i)
		if is_closing then
			return
		end
		save_current_input()
		current_focus_index = i
		if windows[i] and windows[i].win and vim.api.nvim_win_is_valid(windows[i].win) then
			pcall(vim.api.nvim_set_current_win, windows[i].win)
			update_borders()
		end
	end

	local function reset_history_index()
		local field = fields[current_focus_index]
		if field and history_index[field.key] ~= 0 then
			history_index[field.key] = 0
			save_current_input()
		end
	end

	-------------------------------------------------------------------
	-- Bind keys + auto-grow events
	-------------------------------------------------------------------
	for i, w in ipairs(windows) do
		local buf = w.buf

		vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
			buffer = buf,
			callback = function()
				if not is_closing and vim.api.nvim_win_is_valid(w.win) then
					resize_window(w)
					relayout()
					reset_history_index()
				end
			end,
		})

		vim.keymap.set({ "n", "i" }, "<Tab>", function()
			focus((current_focus_index % #windows) + 1)
		end, { buffer = buf })

		vim.keymap.set({ "n", "i" }, "<S-Tab>", function()
			focus((current_focus_index - 2) % #windows + 1)
		end, { buffer = buf })

		vim.keymap.set("i", "<Up>", function()
			navigate_history(1)
		end, { buffer = buf })

		vim.keymap.set("i", "<Down>", function()
			navigate_history(-1)
		end, { buffer = buf })

		vim.keymap.set("n", "<Esc>", close_all, { buffer = buf })
		vim.keymap.set("n", "q", close_all, { buffer = buf })

		vim.keymap.set("n", "<CR>", function()
			if is_closing then
				return
			end

			local result = {}
			for j, field in ipairs(fields) do
				local value = get_value(windows[j].buf)
				result[field.key] = value
				add_to_history(field.key, value)
			end

			close_all()

			if on_submit then
				-- 窗口先关闭，再执行提交（避免同步 curl 期间窗口滞留）
				vim.schedule(function()
					on_submit(result)
				end)
			end
		end, { buffer = buf })
	end

	-------------------------------------------------------------------
	-- Focus the first field
	-------------------------------------------------------------------
	focus(1)
	relayout()
end

return M
