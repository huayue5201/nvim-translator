-- File: lua/translator/state.lua
-- Stores the last translation result + the options it was produced with, so
-- other features (TTS, Anki) can act on it.

local M = {}

local last = nil

--- Store the result of a completed translation.
--- @param trans table  decoded JSON from the backend
--- @param options table  normalized options from cmdline.parse
function M.set(trans, options)
	last = { trans = trans, options = options }
end

--- Get the last translation result, or nil.
function M.get()
	return last
end

--- First non-empty paraphrase across all engine results.
function M.paraphrase()
	if not last then
		return ""
	end
	for _, t in ipairs(last.trans.results or {}) do
		if t.paraphrase and t.paraphrase ~= "" then
			return t.paraphrase
		end
	end
	return ""
end

return M
