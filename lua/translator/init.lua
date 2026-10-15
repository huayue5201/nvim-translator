-- File: lua/translator/init.lua

local cmdline = require("translator.cmdline")
local logger = require("translator.logger")
local job = require("translator.job")
local cache = require("translator.cache")
local config = require("translator.config")

local M = {}

--- Setup: merge user options (called by the plugin manager, e.g. lazy `opts`).
---@param opts table|nil
function M.setup(opts)
	config.setup(opts)
end

---------------------------------------------------------------------
-- OpenAI-compatible LLM provider presets（定义见 config.lua，供 resolve_endpoint 共享）
---------------------------------------------------------------------
local LLM_PRESETS = config.llm_presets

---------------------------------------------------------------------
-- Build the env map passed to the backend for the `llm` engine.
-- The API key travels via env, never via argv, so it cannot leak into logs.
---------------------------------------------------------------------
-- Resolve api_key from the various accepted forms:
--   api_key = "sk-..."            (string)
--   api_key = function() ... end   (lazy, e.g. os.getenv)
--   env = { api_key = ... }        (nested, string or function)
--   api_key_name = "MY_ENV_VAR"    (read from environment by name)
local function resolve_api_key(cfg)
	local key = cfg.api_key
	if type(key) == "function" then
		key = key()
	end

	if (not key or key == "") and type(cfg.env) == "table" then
		key = cfg.env.api_key
		if type(key) == "function" then
			key = key()
		end
	end

	if (not key or key == "") and cfg.api_key_name and cfg.api_key_name ~= "" then
		key = os.getenv(cfg.api_key_name)
	end

	return key or ""
end

local function resolve_model(cfg)
	if cfg.model and cfg.model ~= "" then
		return cfg.model
	end
	if type(cfg.schema) == "table" and cfg.schema.model then
		local m = cfg.schema.model
		if type(m) == "table" and m.default then
			return m.default
		elseif type(m) == "string" then
			return m
		end
	end
	return nil
end

local function resolve_base_url(cfg)
	if cfg.base_url and cfg.base_url ~= "" then
		return cfg.base_url
	end
	if type(cfg.env) == "table" and cfg.env.base_url then
		return cfg.env.base_url
	end
	return nil
end

--- 解析一个 LLM 端点配置（含 provider/name 预设），返回解析后的字段表。
--- 缺少 base_url 或 model 时返回 nil。
local function resolve_endpoint(cfg)
	if type(cfg) ~= "table" then
		return nil
	end

	local provider = cfg.provider or cfg.name
	local base_url = resolve_base_url(cfg)
	local model = resolve_model(cfg)

	if provider and LLM_PRESETS[provider] then
		local preset = LLM_PRESETS[provider]
		base_url = base_url or preset.base_url
		model = model or preset.model
	end

	if not base_url or not model then
		return nil
	end

	return {
		base_url = base_url,
		model = model,
		api_key = resolve_api_key(cfg),
		prompt = cfg.prompt,
		timeout = cfg.timeout,
	}
end

local function build_llm_env()
	local cfg = config.get().llm
	if not cfg or type(cfg) ~= "table" then
		return nil
	end

	local primary = resolve_endpoint(cfg)
	if not primary then
		return nil
	end

	local env = {
		TRANSLATOR_LLM_BASE_URL = primary.base_url,
		TRANSLATOR_LLM_MODEL = primary.model,
	}
	if primary.api_key ~= "" then
		env.TRANSLATOR_LLM_API_KEY = primary.api_key
	end
	if primary.prompt and primary.prompt ~= "" then
		env.TRANSLATOR_LLM_PROMPT = primary.prompt
	end
	if primary.timeout then
		env.TRANSLATOR_LLM_TIMEOUT = tostring(primary.timeout)
	end

	-- 降级端点（可选）：主端点失败/无结果时由 Rust 后端自动尝试
	local fallback = resolve_endpoint(cfg.fallback)
	if fallback then
		env.TRANSLATOR_LLM_FALLBACK_BASE_URL = fallback.base_url
		env.TRANSLATOR_LLM_FALLBACK_MODEL = fallback.model
		if fallback.api_key ~= "" then
			env.TRANSLATOR_LLM_FALLBACK_API_KEY = fallback.api_key
		end
		if fallback.prompt and fallback.prompt ~= "" then
			env.TRANSLATOR_LLM_FALLBACK_PROMPT = fallback.prompt
		end
		if fallback.timeout then
			env.TRANSLATOR_LLM_FALLBACK_TIMEOUT = tostring(fallback.timeout)
		end
	end

	return env
end

---------------------------------------------------------------------
-- Build the env map for the `baidu` engine (official API credentials).
-- Accepts string/function values, an `env` sub-table, or *_name env lookups.
---------------------------------------------------------------------
local function resolve_secret(cfg, value_field, name_field, env_field)
	local v = cfg[value_field]
	if type(v) == "function" then
		v = v()
	end

	if (not v or v == "") and type(cfg.env) == "table" then
		v = cfg.env[env_field]
		if type(v) == "function" then
			v = v()
		end
	end

	if (not v or v == "") and cfg[name_field] and cfg[name_field] ~= "" then
		v = os.getenv(cfg[name_field])
	end

	return v or ""
end

local function build_baidu_env()
	local cfg = config.get().baidu
	if not cfg or type(cfg) ~= "table" then
		return nil
	end

	local appid = resolve_secret(cfg, "appid", "appid_name", "appid")
	local key = resolve_secret(cfg, "key", "key_name", "key")
	if appid == "" and key == "" then
		return nil
	end

	return { TRANSLATOR_BAIDU_APPID = appid, TRANSLATOR_BAIDU_KEY = key }
end

--- Merge all engine-specific env vars (LLM + Baidu) into one map.
local function build_backend_env()
	local env = build_llm_env() or {}
	local baidu = build_baidu_env()
	if baidu then
		for k, v in pairs(baidu) do
			env[k] = v
		end
	end
	if next(env) == nil then
		return nil
	end
	return env
end

---------------------------------------------------------------------
-- Locate the compiled Rust backend binary
---------------------------------------------------------------------
local binary = require("translator.binary")

function M.start(displaymode, opts)
	logger.init()

	local options = cmdline.parse(opts)
	if not options then
		return
	end

	M.translate(options, displaymode)
end

function M.translate(options, displaymode)
	local bin = binary.get()
	if not bin then
		return
	end

	local env = build_backend_env()
	local key = cache.key(options, env)

	-- 命中缓存：直接复用，不启动后端进程。
	if not options.force then
		local cached = cache.get(key)
		if cached then
			job.apply_result(displaymode, cached, options)
			return
		end
	end

	-- Build argv (no shell quoting needed; text is passed as a single element).
	local cmd = {
		bin,
		"translate",
		"--target_lang",
		options.target_lang,
		"--source_lang",
		options.source_lang,
		"--engines",
		table.concat(options.engines, ","),
	}

	local proxy = config.get().proxy_url
	if proxy and proxy ~= "" then
		table.insert(cmd, "--proxy")
		table.insert(cmd, proxy)
	end

	-- Text last, so it can never be mistaken for an option value.
	table.insert(cmd, options.text)

	logger.log(table.concat(cmd, " "))

	job.jobstart(cmd, displaymode, env, options, key)
end

---------------------------------------------------------------------
-- Cancel the in-flight translation request (:TranslateCancel).
---------------------------------------------------------------------
function M.cancel()
	return job.cancel()
end

---------------------------------------------------------------------
-- API-documentation translation (:TranslateApi)
---------------------------------------------------------------------
function M.translate_api(opts)
	opts = opts or {}

	-- Reuse the buffer's filetype as the programming-language hint. The `api`
	-- engine reads it from `source_lang`; non-code buffers fall back to "code".
	local ft = vim.bo.filetype
	local lang = (ft ~= "" and ft ~= "text" and ft ~= "markdown") and ft or "code"

	local extra = vim.trim(opts.args or "")
	local args = "--engines=api --source_lang=" .. lang
	if extra ~= "" then
		args = args .. " " .. extra
	end

	M.start("window", {
		bang = false,
		range = opts.range or 0,
		line1 = opts.line1 or 1,
		line2 = opts.line2 or 1,
		args = args,
	})
end

return M
