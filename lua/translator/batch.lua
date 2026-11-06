-- File: lua/translator/batch.lua
-- Batch translation over a single backend process.
--
-- Texts are sent one per line on stdin; the backend answers with one NDJSON
-- object per text: { "id": <line index>, "text": ..., "results": [...] }.
-- Using one process instead of one per text keeps buffer-wide translations
-- (:TranslateV, blockwise :TranslateR) cheap.

local proc = require("translator.proc")

local M = {}

--- Start a batch translation.
---@param bin string backend executable
---@param env table|nil backend environment
---@param opts { engines:string[], source_lang:string, target_lang:string, proxy:string|nil, concurrency:integer|nil }
---@param texts string[] one text per line (must not contain newlines)
---@param handlers { on_result:fun(id:integer, translations:table), on_error:fun(message:string)|nil }
---@return vim.SystemObj
function M.start(bin, env, opts, texts, handlers)
	local cmd = {
		bin,
		"translate",
		"--batch",
		"--stdin",
		"--target_lang",
		opts.target_lang,
		"--source_lang",
		opts.source_lang,
		"--engines",
		table.concat(opts.engines, ","),
	}
	if opts.concurrency then
		cmd[#cmd + 1] = "--concurrency"
		cmd[#cmd + 1] = tostring(opts.concurrency)
	end
	if opts.proxy and opts.proxy ~= "" then
		cmd[#cmd + 1] = "--proxy"
		cmd[#cmd + 1] = opts.proxy
	end

	local pending = ""
	local function feed(chunk)
		pending = pending .. chunk
		while true do
			local nl = pending:find("\n", 1, true)
			if not nl then
				return
			end
			local line = pending:sub(1, nl - 1)
			pending = pending:sub(nl + 1)
			local ok, obj = pcall(vim.json.decode, line)
			if ok and type(obj) == "table" and type(obj.id) == "number" then
				handlers.on_result(obj.id, obj)
			end
		end
	end

	return vim.system(cmd, {
		env = env,
		stdin = table.concat(texts, "\n") .. "\n",
		text = true,
		[proc.STDOUT_KEY] = function(_, data)
			if data then
				vim.schedule(function()
					feed(data)
				end)
			end
		end,
	}, function(res)
		local stderr = vim.trim(res.stderr or "")
		vim.schedule(function()
			if pending ~= "" then
				feed("\n")
			end
			if stderr ~= "" and handlers.on_error then
				handlers.on_error(stderr)
			end
		end)
	end)
end

return M
