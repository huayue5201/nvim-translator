-- File: lua/translator/init.lua

local cmdline = require("translator.cmdline")
local logger = require("translator.logger")
local job = require("translator.job")

local M = {}

---------------------------------------------------------------------
-- OpenAI-compatible LLM provider presets
---------------------------------------------------------------------
local LLM_PRESETS = {
	deepseek = { base_url = "https://api.deepseek.com", model = "deepseek-chat" },
	openai = { base_url = "https://api.openai.com/v1", model = "gpt-4o-mini" },
	ollama = { base_url = "http://127.0.0.1:11434/v1", model = "llama3.1" },
	qwen = { base_url = "https://dashscope.aliyuncs.com/compatible-mode/v1", model = "qwen-plus" },
	kimi = { base_url = "https://api.moonshot.cn/v1", model = "moonshot-v1-8k" },
	doubao = { base_url = "https://ark.cn-beijing.volces.com/api/v3", model = "doubao-pro-32k" },
}

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

local function build_llm_env()
	local cfg = vim.g.translator_llm
	if not cfg or type(cfg) ~= "table" then
		return nil
	end

	-- provider 与 name 互为别名
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

	local env = {
		TRANSLATOR_LLM_BASE_URL = base_url,
		TRANSLATOR_LLM_MODEL = model,
	}

	local api_key = resolve_api_key(cfg)
	if api_key ~= "" then
		env.TRANSLATOR_LLM_API_KEY = api_key
	end
	if cfg.prompt and cfg.prompt ~= "" then
		env.TRANSLATOR_LLM_PROMPT = cfg.prompt
	end
	if cfg.timeout then
		env.TRANSLATOR_LLM_TIMEOUT = tostring(cfg.timeout)
	end

	return env
end

---------------------------------------------------------------------
-- Locate the compiled Rust backend binary
---------------------------------------------------------------------
local binary = require("translator.binary")

function M.start(displaymode, opts, range, line1, line2, argstr)
	logger.init()

	-- Backwards compatibility with the old signature:
	--   start(displaymode, bang, range, line1, line2, argstr)
	-- New signature (used by the built-in commands):
	--   start(displaymode, opts)  -- opts = { bang, range, line1, line2, args }
	if type(opts) ~= "table" then
		opts = {
			bang = opts,
			range = range or 0,
			line1 = line1 or 1,
			line2 = line2 or 1,
			args = argstr or "",
		}
	end

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

	if vim.g.translator_proxy_url and vim.g.translator_proxy_url ~= "" then
		table.insert(cmd, "--proxy")
		table.insert(cmd, vim.g.translator_proxy_url)
	end

	-- Text last, so it can never be mistaken for an option value.
	table.insert(cmd, options.text)

	logger.log(table.concat(cmd, " "))

	job.jobstart(cmd, displaymode, build_llm_env(), options)
end

return M
