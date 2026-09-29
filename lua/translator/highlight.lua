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
	engine = "TranslatorEngine",
	phonetic = "TranslatorPhonetic",
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
	TranslatorEngine = { link = "Title", default = true },
	TranslatorPhonetic = { link = "Comment", default = true },
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

--- 给整个 buffer 按角色上色（整行高亮，兼容 fit_lines 的居中/换行）
---@param bufnr integer
function M.apply(bufnr)
	M.setup()
	if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
		return
	end

	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	for i, line in ipairs(lines) do
		local role = M.role_of(line)
		local group = role and group_for(role)
		if group then
			vim.api.nvim_buf_set_extmark(bufnr, NS, i - 1, 0, { line_hl_group = group })
		end
	end
end

--- 命名空间 id（测试用）
---@return integer
function M.namespace()
	return NS
end

return M
