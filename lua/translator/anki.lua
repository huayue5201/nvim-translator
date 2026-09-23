-- File: lua/translator/anki.lua
-- Add the last translation to Anki via AnkiConnect (https://git.sr.ht/~foosoft/anki-connect).
-- Requires: Anki running + the "AnkiConnect" addon installed (code 2055492159).

local util = require("translator.util")
local state = require("translator.state")

local M = {}

local function config()
	return {
		port = vim.g.translator_anki_port or 8765,
		deck = vim.g.translator_anki_deck or "翻译",
		model = vim.g.translator_anki_model or "translator",
	}
end

local function request(action, params)
	local cfg = config()
	local body = vim.json.encode({ action = action, version = 6, params = params })
	local out = vim.fn.system({
		"curl",
		"-s",
		"-m",
		"5",
		"-H",
		"Content-Type: application/json",
		"http://127.0.0.1:" .. cfg.port,
		"-d",
		body,
	})

	if vim.v.shell_error ~= 0 then
		return nil, "AnkiConnect 不可达：请确认 Anki 正在运行，且已安装 AnkiConnect 插件"
	end

	local ok, resp = pcall(vim.json.decode, out)
	if not ok then
		return nil, "AnkiConnect 响应解析失败"
	end
	-- vim.json.decode maps JSON null to vim.NIL; treat that as "no error".
	if resp.error and resp.error ~= vim.NIL then
		return nil, tostring(resp.error)
	end
	-- Normalize a null result (e.g. duplicate skipped by addNote) to Lua nil.
	local result = resp.result
	if result == vim.NIL then
		result = nil
	end
	return result, nil
end

local function ensure_deck(deck)
	return request("createDeck", { deck = deck })
end

local function ensure_model(model)
	return request("createModel", {
		modelName = model,
		inOrderFields = { "Front", "Back", "Phonetic", "Example" },
		isCloze = false,
		cardTemplates = {
			{
				Name = "Card 1",
				Front = "{{Front}}",
				Back = "{{FrontSide}}<hr id=answer>{{Back}}"
					.. "{{#Phonetic}}<div>[{{Phonetic}}]</div>{{/Phonetic}}"
					.. "{{#Example}}<div class='example'>{{Example}}</div>{{/Example}}",
			},
		},
	})
end

local function build_note(trans, cfg)
	local text = trans.text or ""
	local paraphrase = ""
	local explains = {}
	local phonetic = ""

	for _, t in ipairs(trans.results or {}) do
		if paraphrase == "" and t.paraphrase and t.paraphrase ~= "" then
			paraphrase = t.paraphrase
		end
		if #explains == 0 and t.explains then
			for _, e in ipairs(t.explains) do
				if e and e ~= "" then
					table.insert(explains, e)
				end
			end
		end
		if phonetic == "" and t.phonetic and t.phonetic ~= "" then
			phonetic = t.phonetic
		end
	end

	local back = paraphrase
	if #explains > 0 then
		local expl = table.concat(explains, "\n")
		back = back ~= "" and (back .. "\n" .. expl) or expl
	end

	return {
		deckName = cfg.deck,
		modelName = cfg.model,
		fields = {
			Front = text,
			Back = back,
			Phonetic = phonetic,
			Example = "",
		},
		tags = { "translator" },
		options = { allowDuplicate = false },
	}
end

--- `:TranslateA` — add the last translation to Anki.
function M.add()
	local s = state.get()
	if not s or not s.trans or not s.trans.text or s.trans.text == "" then
		util.show_msg("没有可添加的翻译（先翻译一次）", "warning")
		return
	end

	local cfg = config()

	local _, err = ensure_deck(cfg.deck)
	if err then
		util.show_msg("创建牌组失败：" .. err, "error")
		return
	end

	local _, err2 = ensure_model(cfg.model)
	if err2 then
		util.show_msg("创建笔记模板失败：" .. err2, "error")
		return
	end

	local note = build_note(s.trans, cfg)
	local result, err3 = request("addNote", { note = note })
	if err3 then
		util.show_msg("添加到 Anki 失败：" .. err3, "error")
		return
	end

	if result == nil then
		util.show_msg("已存在，跳过：" .. note.fields.Front, "warning")
	else
		util.show_msg("已添加到 Anki：" .. note.fields.Front)
	end
end

return M
