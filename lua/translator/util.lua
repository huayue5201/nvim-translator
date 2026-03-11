-- FileName: util.lua
-- Author: voldikss <dyzplus@gmail.com> (translated to Lua)
-- GitHub: https://github.com/voldikss
-- Description: Utility functions for translator plugin

local M = {}

function M.echo(group, msg)
	if msg == "" then
		return
	end
	vim.cmd(string.format("echohl %s", group))
	vim.api.nvim_echo({ { msg } }, false, {})
	vim.cmd('echon " "')
	vim.cmd("echohl NONE")
end

function M.echon(group, msg)
	if msg == "" then
		return
	end
	vim.cmd(string.format("echohl %s", group))
	vim.api.nvim_echo({ { msg, "" } }, false, {})
	vim.cmd('echon " "')
	vim.cmd("echohl NONE")
end

function M.show_msg(message, msg_type)
	if msg_type == nil then
		msg_type = "info"
	end

	local msg_str
	if type(message) ~= "string" then
		msg_str = vim.inspect(message)
	else
		msg_str = message
	end

	M.echo("Constant", "[vim-translator]")

	if msg_type == "info" then
		M.echon("Normal", msg_str)
	elseif msg_type == "warning" then
		M.echon("WarningMsg", msg_str)
	elseif msg_type == "error" then
		M.echon("Error", msg_str)
	end
end

function M.pad(text, width, char)
	local text_width = vim.fn.strdisplaywidth(text)
	local padding_size = math.floor((width - text_width) / 2)
	local char_width = vim.fn.strdisplaywidth(char)
	local padding_count = math.floor(padding_size / char_width)
	local padding = string.rep(char, padding_count)

	local padend_count = (width - text_width) % 2
	local padend = string.rep(char, padend_count)

	local result = padding .. text .. padding
	if width >= vim.fn.strdisplaywidth(result) + vim.fn.strdisplaywidth(padend) then
		result = result .. padend
	end
	return result
end

function M.fit_lines(linelist, width)
	for i, line in ipairs(linelist) do
		if string.match(line, "^───") and width > vim.fn.strdisplaywidth(line) then
			linelist[i] = M.pad(line, width, "─")
		elseif string.match(line, "^⟦") and width > vim.fn.strdisplaywidth(line) then
			linelist[i] = M.pad(line, width, " ")
		end
	end
	return linelist
end

function M.visual_select(range, line1, line2)
	local lines
	if range == 0 then
		lines = { vim.fn.expand("<cword>") }
	elseif range == 1 then
		lines = { vim.fn.getline(".") }
	else
		if line1 == line2 then
			-- https://vi.stackexchange.com/a/11028/17515
			local pos1 = vim.fn.getpos("'<")
			local pos2 = vim.fn.getpos("'>")
			local lnum1, col1 = pos1[2], pos1[3]
			local lnum2, col2 = pos2[2], pos2[3]

			lines = vim.fn.getline(lnum1, lnum2)
			if vim.tbl_isempty(lines) then
				M.show_msg("No lines were selected", "error")
				return ""
			end
			lines[#lines] = string.sub(lines[#lines], 1, col2)
			lines[1] = string.sub(lines[1], col1)
		else
			lines = vim.fn.getline(line1, line2)
		end
	end
	return table.concat(lines, "\n")
end

function M.safe_trim(text)
	return string.gsub(text, "^[%s]+|[%s]+$", "")
end

function M.text_proc(text)
	local result = string.gsub(text, "\n", " ")
	result = string.gsub(result, "\n\r", " ")
	result = string.gsub(result, "^%s+", "")
	result = string.gsub(result, "%s+$", "")
	result = string.gsub(result, '"', '\\"')
	result = string.format('"%s"', result)
	return result
end

return M
