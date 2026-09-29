-- File: lua/translator/highlight.lua
-- Restrained line-level highlights for the translation panel.
--
-- 克制风：只给「结构」上色，正文保持默认 ——
--   原文   → 弱化（Comment）
--   引擎头 → 强调（Title）
--   音标   → 弱化（Comment）
--
-- 全部走 link + default=true；用户可用 vim.g.translator_highlights 覆盖，
-- 配色方案也能自由接管。

local M = {}

-- 角色 → 默认高亮组
local DEFAULT_ROLES = {
	source = "TranslatorSource",
	source_text = "TranslatorSourceText",
	engine = "TranslatorEngine",
	phonetic = "TranslatorPhonetic",
	marker = "TranslatorMarker",
}

-- 基础/角色高亮组（default=true：不覆盖用户或配色方案的定义）
local BASE_GROUPS = {
	-- 窗口底色
	Translator = { link = "NormalFloat", default = true },
	TranslatorPreview = { link = "NormalFloat", default = true },
	-- footer 文字
	FloatFooter = { link = "Comment", default = true },
	-- 内容角色
	TranslatorSource = { link = "Comment", default = true },
	TranslatorSourceText = { link = "Identifier", default = true },
	TranslatorEngine = { link = "Title", default = true },
	TranslatorPhonetic = { link = "Comment", default = true },
	TranslatorMarker = { link = "Special", default = true },
}

local NS = vim.api.nvim_create_namespace("translator_highlight")

--- 定义基础高亮组（幂等）
function M.setup()
	for name, opts in pairs(BASE_GROUPS) do
		vim.api.nvim_set_hl(0, name, opts)
	end
end

--- 角色对应的实际高亮组（支持 vim.g.translator_highlights 覆盖；false/"" = 关闭）
---@param role string
---@return string|nil
local function group_for(role)
	local overrides = vim.g.translator_highlights
	if type(overrides) == "table" and overrides[role] ~= nil then
		if overrides[role] == false or overrides[role] == "" then
			return nil
		end
		return overrides[role]
	end
	return DEFAULT_ROLES[role]
end

--- 按渲染后的行前缀判定角色（前缀是插件自身产出的语义标记）
---@param line string
---@return string|nil
function M.role_of(line)
	if line:match("^%s*⟦") then
		return "source"
	end
	if line:match("^%s*─") then
		return "engine"
	end
	if line:match("^%s*•%s*%[") then
		return "phonetic"
	end
	return nil
end

--- 行首标记（• / ↳）的字节范围；返回 0-based 起始与独占结束列
---@param line string
---@return integer|nil, integer|nil
local function marker_span(line)
	for _, m in ipairs({ "•", "↳" }) do
		local s, e = line:find(m, 1, true)
		if s then
			return s - 1, e
		end
	end
	return nil, nil
end

--- 原文文本（⟦ … ⟧ 内部）的字节范围；返回 0-based 起始与独占结束列
---@param line string
---@return integer|nil, integer|nil
local function source_span(line)
	local _, l_end = line:find("⟦", 1, true)
	if not l_end then
		return nil, nil
	end
	local r_start = line:find("⟧", l_end + 1, true)
	if not r_start then
		return nil, nil
	end
	return l_end, r_start - 1
end

--- 给整个 buffer 上色（角色=整行；原文/标记=行内局部）
---@param bufnr integer
function M.apply(bufnr)
	M.setup()
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		local row = i - 1

		-- 整行角色（原文行 / 引擎头 / 音标）
		local role = M.role_of(line)
		local line_group = role and group_for(role)
		if line_group then
			vim.api.nvim_buf_set_extmark(bufnr, NS, row, 0, { line_hl_group = line_group })
		end

		-- 被译对象：⟦ … ⟧ 内部的原文用强调色（覆盖整行的弱化）
		local sstart, send = source_span(line)
		if sstart then
			local st_group = group_for("source_text")
			if st_group then
				vim.api.nvim_buf_set_extmark(bufnr, NS, row, sstart, { end_col = send, hl_group = st_group })
			end
		end

		-- 行首标记（• / ↳）只染标记本身
		local mstart, mend = marker_span(line)
		if mstart then
			local marker_group = group_for("marker")
			if marker_group then
				vim.api.nvim_buf_set_extmark(bufnr, NS, row, mstart, { end_col = mend, hl_group = marker_group })
			end
		end
	end
end

--- 命名空间 id（测试用）
---@return integer
function M.namespace()
	return NS
end

return M
