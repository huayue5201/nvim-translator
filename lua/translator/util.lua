-- FileName: util.lua
-- Description: Pure Neovim utility functions for translator.nvim

local M = {}

---------------------------------------------------------------------
-- Message helpers (Neovim native)
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
-- Center padding for lines
---------------------------------------------------------------------
function M.pad(text, width, char)
	local text_width = vim.fn.strdisplaywidth(text)
	local pad_size = math.max(0, width - text_width)
	local left = math.floor(pad_size / 2)
	local right = pad_size - left
	return string.rep(char, left) .. text .. string.rep(char, right)
end

---------------------------------------------------------------------
-- Wrap long lines to fit width
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
		local test_line = current_line == "" and word or current_line .. word
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
-- Fit lines to width (for pretty window rendering)
---------------------------------------------------------------------
function M.fit_lines(lines, width)
	local result = {}

	for _, line in ipairs(lines) do
		if line:match("^───") then
			-- 分隔线：居中填充
			local w = vim.fn.strdisplaywidth(line)
			if w < width then
				table.insert(result, M.pad(line, width, "─"))
			else
				table.insert(result, line)
			end
		elseif line:match("^⟦") then
			-- 标题行：居中填充空格
			local w = vim.fn.strdisplaywidth(line)
			if w < width then
				table.insert(result, M.pad(line, width, " "))
			else
				table.insert(result, line)
			end
		else
			-- 普通行：自动换行
			local wrapped = M.wrap_line(line, width - 4) -- 留出缩进空间
			for _, wrapped_line in ipairs(wrapped) do
				table.insert(result, "  " .. wrapped_line)
			end
		end
	end

	return result
end

---------------------------------------------------------------------
-- Pure Neovim Visual selection (v / V / CTRL-V)
-- With full safety checks (never returns nil)
---------------------------------------------------------------------
function M.get_visual_selection()
	-- 检查是否在可视模式
	local mode = vim.api.nvim_get_mode().mode
	if not mode:match("^[vV\x16]") then -- v, V, 或 Ctrl-V
		return ""
	end

	-- 获取可视区域的起始和结束位置
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")

	if not start_pos or not end_pos or start_pos[2] == 0 or end_pos[2] == 0 then
		return ""
	end

	local srow = start_pos[2] -- 1-based line number
	local scol = start_pos[3] -- 1-based column
	local erow = end_pos[2]
	local ecol = end_pos[3]

	-- 处理反向选择
	if erow < srow or (erow == srow and ecol < scol) then
		srow, erow = erow, srow
		scol, ecol = ecol, scol
	end

	-- 获取所有选中的行
	local lines = vim.api.nvim_buf_get_lines(0, srow - 1, erow, false)
	if #lines == 0 then
		return ""
	end

	-- 根据可视模式处理
	if mode == "V" then -- 行可视模式
		-- 直接返回所有行，保留换行符
		return table.concat(lines, "\n")
	elseif mode == "\x16" then -- 块可视模式 (Ctrl-V)
		local result = {}
		for _, line in ipairs(lines) do
			local line_len = #line
			local start_col = math.min(scol, line_len + 1)
			local end_col = math.min(ecol, line_len)

			if start_col <= end_col then
				table.insert(result, line:sub(start_col, end_col))
			else
				table.insert(result, "") -- 空行
			end
		end
		return table.concat(result, "\n")
	else -- 字符可视模式 (v)
		if #lines == 1 then
			-- 单行选择
			return lines[1]:sub(scol, ecol)
		else
			-- 多行选择
			local result_lines = {}

			-- 第一行
			result_lines[1] = lines[1]:sub(scol)

			-- 中间行
			for i = 2, #lines - 1 do
				table.insert(result_lines, lines[i])
			end

			-- 最后一行（如果不止一行）
			if #lines > 1 then
				table.insert(result_lines, lines[#lines]:sub(1, ecol))
			end

			return table.concat(result_lines, "\n")
		end
	end
end

-- Backward compatibility for old code
M.visual_select = M.get_visual_selection

---------------------------------------------------------------------
-- Safe trim
---------------------------------------------------------------------
function M.safe_trim(text)
	return text:gsub("^%s+", ""):gsub("%s+$", "")
end

---------------------------------------------------------------------
-- Escape text for shell or API
---------------------------------------------------------------------
function M.text_proc(text)
	local t = text:gsub("\n", " ")
	t = t:gsub("\r", " ")
	t = t:gsub("^%s+", "")
	t = t:gsub("%s+$", "")
	t = t:gsub('"', '\\"')
	return string.format('"%s"', t)
end

return M
