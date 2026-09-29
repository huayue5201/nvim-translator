-- File: lua/translator/cache.lua
-- Translation result cache with TTL.
--
--   key   = sha256(text + source_lang + target_lang + engines + base_url + model + prompt)
--   value = { t = 写入时间戳, v = 解码后的 translations 表 }
--
-- 配置：
--   require("translator").setup({ cache = { enable = false, ttl = 0 } })

local M = {}

local config = require("translator.config")

local DEFAULT_TTL = 7 * 24 * 60 * 60 -- 7 天
local MAX_ENTRIES = 500

local function cache_path()
	local dir = vim.fn.stdpath("data") .. "/translator"
	if vim.fn.isdirectory(dir) == 0 then
		vim.fn.mkdir(dir, "p")
	end
	return dir .. "/cache.json"
end

local CACHE = cache_path()
local store = nil -- 懒加载：{ [key] = { t = <time>, v = <translations> } }

local function load()
	if store then
		return store
	end
	store = {}
	if vim.fn.filereadable(CACHE) == 1 then
		local content = table.concat(vim.fn.readfile(CACHE), "\n")
		local ok, data = pcall(vim.json.decode, content)
		if ok and type(data) == "table" then
			store = data
		end
	end
	return store
end

local function save()
	local f = io.open(CACHE, "w")
	if not f then
		return
	end
	f:write(vim.json.encode(load()))
	f:close()
end

local function ttl()
	local v = tonumber(config.get().cache.ttl)
	if v == nil then
		return DEFAULT_TTL
	end
	return v
end

local function enabled()
	return config.get().cache.enable ~= false
end

--- 稳定哈希（sha256，失败时退回 djb2）
---@param s string
---@return string
local function hash(s)
	local ok, h = pcall(vim.fn.sha256, s)
	if ok and type(h) == "string" and h ~= "" then
		return h
	end
	local acc = 5381
	for i = 1, #s do
		acc = (acc * 33 + s:byte(i)) % 4294967296
	end
	return string.format("%08x", acc)
end

--- 由翻译参数 + LLM env 计算缓存 key
---@param options table
---@param env table|nil
---@return string
function M.key(options, env)
	env = env or {}
	local engines = vim.deepcopy(options.engines or {})
	table.sort(engines)

	local parts = {
		vim.trim(options.text or ""),
		options.source_lang or "",
		options.target_lang or "",
		table.concat(engines, ","),
		tostring(env.TRANSLATOR_LLM_BASE_URL or ""),
		tostring(env.TRANSLATOR_LLM_MODEL or ""),
		tostring(env.TRANSLATOR_LLM_PROMPT or ""),
	}
	return hash(table.concat(parts, "\1"))
end

--- 读取缓存（缺失 / 过期 / 已禁用 → nil）
---@param key string
---@return table|nil
function M.get(key)
	if not enabled() or not key then
		return nil
	end
	local entry = load()[key]
	if type(entry) ~= "table" then
		return nil
	end
	local t = ttl()
	if t > 0 and (os.time() - (entry.t or 0)) > t then
		return nil
	end
	return entry.v
end

--- 写入缓存（覆盖并刷新时间戳），必要时按最旧时间戳裁剪
---@param key string
---@param translations table
function M.set(key, translations)
	if not enabled() or not key or type(translations) ~= "table" then
		return
	end

	local s = load()
	s[key] = { t = os.time(), v = translations }

	local count = 0
	for _ in pairs(s) do
		count = count + 1
	end
	if count > MAX_ENTRIES then
		local keys = vim.tbl_keys(s)
		table.sort(keys, function(a, b)
			return (s[a].t or 0) < (s[b].t or 0)
		end)
		for i = 1, count - MAX_ENTRIES do
			s[keys[i]] = nil
		end
	end

	save()
end

--- 清空缓存
function M.clear()
	store = {}
	save()
end

--- 当前缓存条数
---@return integer
function M.size()
	return vim.tbl_count(load())
end

--- 缓存文件路径（调试用）
---@return string
function M.path()
	return CACHE
end

return M
