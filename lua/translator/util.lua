-- File: lua/translator/util.lua
-- Description: Pure Neovim utility functions for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Message helpers
---------------------------------------------------------------------
function M.echo(group, msg)
	if not msg or msg == "" then
		return
	end
	vim.api.nvim_echo({ { msg, group } }, false, {})
end

function M.show_msg(message, msg_type)
	local msg = type(message) == "string" and message or vim.inspect(message)
	local prefix = "[translator] "

	if msg_type == "error" then
		vim.api.nvim_echo({ { prefix, "ErrorMsg" }, { msg } }, false, {})
	elseif msg_type == "warning" then
		vim.api.nvim_echo({ { prefix, "WarningMsg" }, { msg } }, false, {})
	else
		vim.api.nvim_echo({ { prefix, "Constant" }, { msg } }, false, {})
	end
end

---------------------------------------------------------------------
-- String helpers
---------------------------------------------------------------------
function M.safe_trim(text)
	return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---------------------------------------------------------------------
-- FIXED: 不再增加 shell quote
-- 因为 jobstart 使用 argv 方式调用 python
---------------------------------------------------------------------
function M.text_proc(text)
	local t = text:gsub("\n", " ")
	t = t:gsub("\r", " ")
	t = t:gsub("^%s+", "")
	t = t:gsub("%s+$", "")
	return t
end

---------------------------------------------------------------------
-- Center padding
---------------------------------------------------------------------
function M.pad(text, width, char)
	local text_width = vim.fn.strdisplaywidth(text)
	local pad_size = math.max(0, width - text_width)

	local left = math.floor(pad_size / 2)
	local right = pad_size - left

	return string.rep(char, left) .. text .. string.rep(char, right)
end

---------------------------------------------------------------------
-- Wrap long lines
---------------------------------------------------------------------
function M.wrap_line(line, width)
	if vim.fn.strdisplaywidth(line) <= width then
		return { line }
	end

	local words = {}

	for word in line:gmatch("%S+%s*") do
		table.insert(words, word)
	end

	local lines = {}
	local current_line = ""

	for _, word in ipairs(words) do
		local test_line

		if current_line == "" then
			test_line = word
		else
			test_line = current_line .. word
		end

		if vim.fn.strdisplaywidth(test_line) <= width then
			current_line = test_line
		else
			if current_line ~= "" then
				table.insert(lines, current_line)
			end
			current_line = word
		end
	end

	if current_line ~= "" then
		table.insert(lines, current_line)
	end

	return lines
end

---------------------------------------------------------------------
-- Fit lines for window rendering
---------------------------------------------------------------------
function M.fit_lines(lines, width)
	local result = {}

	for _, line in ipairs(lines) do
		if line:match("^───") then
			local w = vim.fn.strdisplaywidth(line)

			if w < width then
				table.insert(result, M.pad(line, width, "─"))
			else
				table.insert(result, line)
			end
		elseif line:match("^⟦") then
			local w = vim.fn.strdisplaywidth(line)

			if w < width then
				table.insert(result, M.pad(line, width, " "))
			else
				table.insert(result, line)
			end
		else
			local wrapped = M.wrap_line(line, width - 4)

			for _, wrapped_line in ipairs(wrapped) do
				table.insert(result, "  " .. wrapped_line)
			end
		end
	end

	return result
end

---------------------------------------------------------------------
-- Visual selection (v / V / CTRL-V)
---------------------------------------------------------------------
function M.get_visual_selection()
	local mode = vim.api.nvim_get_mode().mode

	if not mode:match("^[vV\22]") then
		return ""
	end

	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	if not start_pos or not end_pos or start_pos[2] == 0 or end_pos[2] == 0 then
		return ""
	end

	local srow = start_pos[2]
	local scol = start_pos[3]
	local erow = end_pos[2]
	local ecol = end_pos[3]

	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end

	local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)

	if #lines == 0 then
		return ""
	end

	if mode == "V" then
		return table.concat(lines, "\n")
	elseif mode == "\22" then
		local result = {}

		for _, line in ipairs(lines) do
			local line_len = #line

			local start_col = math.min(scol, line_len + 1)
			local end_col = math.min(ecol, line_len)

			if start_col <= end_col then
				table.insert(result, line:sub(start_col, end_col))
			else
				table.insert(result, "")
			end
		end

		return table.concat(result, "\n")
	else
		if #lines == 1 then
			return lines[1]:sub(scol, ecol)
		else
			local result_lines = {}

			result_lines[1] = lines[1]:sub(scol)

			for i = 2, #lines - 1 do
				table.insert(result_lines, lines[i])
			end

			if #lines > 1 then
				table.insert(result_lines, lines[#lines]:sub(1, ecol))
			end

			return table.concat(result_lines, "\n")
		end
	end
end

---------------------------------------------------------------------
-- Backward compatibility
---------------------------------------------------------------------
M.visual_select = M.get_visual_selection

return M
