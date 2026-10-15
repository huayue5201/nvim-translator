-- File: lua/translator/config.lua
-- Central configuration: defaults + setup(opts) + get().
--
-- 用法（lazy.nvim）：
--   { "huayue5201/nvim-translator", opts = { cache = { ttl = 0 }, bilingual = true } }
-- lazy 会调用 require("translator").setup(opts)。
-- 未调用 setup 时，get() 返回内置默认值。

local M = {}

--- OpenAI-compatible LLM provider presets（provider/name 可直接引用）
M.llm_presets = {
	deepseek = { base_url = "https://api.deepseek.com", model = "deepseek-chat" },
	openai = { base_url = "https://api.openai.com/v1", model = "gpt-4o-mini" },
	ollama = { base_url = "http://127.0.0.1:11434/v1", model = "llama3.1" },
	qwen = { base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1", model = "qwen-plus" },
	kimi = { base_url = "https://api.moonshot.cn/v1", model = "moonshot-v1-8k" },
	doubao = { base_url = "https://ark.cn-beijing.volces.com/api/v3", model = "doubao-pro-32k" },
}

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
---@field baidu table -- 百度翻译开放平台凭证：{ appid, key }（或 appid_name/key_name 读环境变量）
---@field incremental boolean -- 多引擎结果增量显示（结果到达即增长浮窗）
---@field window translator.WindowConfig
---@field cache translator.CacheConfig
---@field history { enable: boolean }
---@field spinner translator.SpinnerConfig
---@field cancel_key string|false -- key that aborts an in-flight request; false disables
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
	-- 本地 LLM 引擎配置。可选 server 字段启用“按需启动 + 空闲回收”：
	--   llm.server = {
	--     cmd = { "/opt/homebrew/bin/llama-server", "-m", "<model.gguf>", ... },
	--     health = "http://127.0.0.1:8080/health", -- 健康检查地址
	--     wait = 120,      -- 等待服务就绪的最长秒数
	--     poll_ms = 1000,  -- 健康检查轮询间隔（毫秒）
	--     stamp = vim.fn.expand("~/.cache/translator/llm.last_active"), -- 活跃时间戳
	--   }
	llm = {},
	-- 百度翻译开放平台（支持整句翻译）。配置 appid/key 后 baidu 引擎走官方 API，
	-- 否则回退到免费的 /sug 词典接口（仅支持单词）。支持多种写法：
	--   baidu = { appid = "...", key = "..." }
	--   baidu = { appid = function() ... end, key = function() ... end }
	--   baidu = { appid_name = "MY_APPID", key_name = "MY_KEY" }  -- 读环境变量名
	--   baidu = { env = { appid = "...", key = "..." } }
	baidu = {},
	-- 多引擎结果增量显示：第一个引擎返回即弹出浮窗，之后每个结果到达就
	-- 追加一段、窗口增高（到达顺序），末尾进度行显示“还有 N 个翻译中…”。
	-- 关闭时回退为“全部返回后一次性显示”。
	incremental = true,
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
	-- 翻译进行中临时绑定此键以取消请求（仅 n/v 模式，且用户未占用时）；false/"" 关闭。
	cancel_key = "<Esc>",
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
