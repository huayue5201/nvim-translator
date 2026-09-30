-- File: lua/translator/config.lua
-- Central configuration: defaults + setup(opts) + get().
--
-- 用法（lazy.nvim）：
--   { "huayue5201/nvim-translator", opts = { cache = { ttl = 0 }, bilingual = true } }
-- lazy 会调用 require("translator").setup(opts)。
-- 未调用 setup 时，get() 返回内置默认值。

local M = {}

---@class translator.WindowConfig
---@field type "float"|"preview"
---@field max_width integer|number
---@field max_height integer|number

---@class translator.CacheConfig
---@field enable boolean
---@field ttl integer -- seconds; 0 = never expire

---@class translator.SpinnerConfig
---@field enable boolean
---@field frames? string[]
---@field interval? integer

---@class translator.AnkiConfig
---@field port integer
---@field deck string
---@field model string

---@class translator.Config
---@field source_lang string
---@field target_lang string
---@field bilingual boolean
---@field engines string[]|string|nil -- nil → derived from target_lang
---@field proxy_url string
---@field request_timeout integer -- ms; <= 0 = no timeout
---@field llm table
---@field window translator.WindowConfig
---@field cache translator.CacheConfig
---@field history { enable: boolean }
---@field spinner translator.SpinnerConfig
---@field tts { engine: "say"|"google" }
---@field anki translator.AnkiConfig
---@field highlights table
---@field debug boolean

local defaults = {
	source_lang = "auto",
	target_lang = "zh",
	bilingual = false,
	-- engines 默认按 target_lang 推导（见 setup）
	proxy_url = "",
	-- 单次后端请求的超时（毫秒）；<= 0 表示不限制。
	request_timeout = 15000,
	llm = {},
	window = {
		type = "float",
		max_width = 999,
		max_height = 999,
	},
	cache = {
		enable = true,
		ttl = 7 * 24 * 60 * 60,
	},
	history = {
		enable = false,
	},
	spinner = {
		enable = true,
	},
	tts = {
		engine = "say",
	},
	anki = {
		port = 8765,
		deck = "翻译",
		model = "translator",
	},
	highlights = {},
	debug = false,
}

local conf = nil

---@param target_lang string|nil
---@return string[]
local function default_engines(target_lang)
	if target_lang and tostring(target_lang):match("zh") then
		return { "bing", "google", "haici", "youdao" }
	end
	return { "google" }
end

--- Merge user config over the defaults. Safe to call once at load.
---@param user table|nil
---@return translator.Config
function M.setup(user)
	conf = vim.tbl_deep_extend("force", {}, defaults, user or {})
	if conf.engines == nil then
		conf.engines = default_engines(conf.target_lang)
	end
	if type(conf.engines) == "string" then
		conf.engines = vim.split(conf.engines, ",", { trimempty = true })
	end
	return conf
end

--- Current merged config (lazily initialized to the defaults).
---@return translator.Config
function M.get()
	if not conf then
		M.setup()
	end
	return conf
end

return M
