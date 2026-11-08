-- File: lua/translator/anki.lua
-- Add the last translation to Anki via AnkiConnect (https://git.sr.ht/~foosoft/anki-connect).
-- Before saving, an interactive popup lets you edit the note fields.
-- Requires: Anki running + the "AnkiConnect" addon installed (code 2055492159).

local util = require("translator.util")
local state = require("translator.state")
local config_mod = require("translator.config")
local proc = require("translator.proc")

local async = vim.async

local M = {}

local function config()
	local c = config_mod.get().anki
	return { port = c.port, deck = c.deck, model = c.model }
end

local function request(action, params)
	local cfg = config()
	local body = vim.json.encode({ action = action, version = 6, params = params })
	local res = async.await(async.run(proc.run, {
		"curl",
		"-s",
		"-m",
		"5",
		"-H",
		"Content-Type: application/json",
		"http://127.0.0.1:" .. cfg.port,
		"-d",
		body,
	}))

	if res.code ~= 0 then
		return nil, "AnkiConnect unreachable: make sure Anki is running and the AnkiConnect add-on is installed"
	end

	local ok, resp = pcall(vim.json.decode, res.stdout)
	if not ok then
		return nil, "Failed to parse AnkiConnect response"
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

---------------------------------------------------------------------
-- Default field values, derived from the last translation.
---------------------------------------------------------------------
local function default_fields(trans)
	local front = trans.text or ""
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
		Front = front,
		Back = back,
		Phonetic = phonetic,
		Example = "",
	}
end

local function build_note(fields, cfg)
	return {
		deckName = cfg.deck,
		modelName = cfg.model,
		fields = {
			Front = fields.Front or "",
			Back = fields.Back or "",
			Phonetic = fields.Phonetic or "",
			Example = fields.Example or "",
		},
		tags = { "translator" },
		options = { allowDuplicate = false },
	}
end

---------------------------------------------------------------------
-- Persist the (possibly edited) fields to Anki.
---------------------------------------------------------------------
local function submit(fields)
	local cfg = config()

	local _, err = ensure_deck(cfg.deck)
	if err then
		util.show_msg("Failed to create deck: " .. err, "error")
		return
	end

	local _, err2 = ensure_model(cfg.model)
	if err2 then
		util.show_msg("Failed to create note type: " .. err2, "error")
		return
	end

	local note = build_note(fields, cfg)
	local result, err3 = request("addNote", { note = note })
	if err3 then
		util.show_msg("Failed to add to Anki: " .. err3, "error")
		return
	end

	if result == nil then
		util.show_msg("Already exists, skipped: " .. note.fields.Front, "warning")
	else
		util.show_msg("Added to Anki: " .. note.fields.Front)
	end
end

--- `:TranslateA` — edit then add the last translation to Anki.
function M.add()
	local s = state.get()
	if not s or not s.trans or not s.trans.text or s.trans.text == "" then
		util.show_msg("No translation to add (translate first)", "warning")
		return
	end

	local defaults = default_fields(s.trans)

	local fields = {
		{ key = "Front", label = "Original", value = defaults.Front },
		{ key = "Back", label = "Translation", value = defaults.Back },
		{ key = "Phonetic", label = "Phonetic", value = defaults.Phonetic },
		{ key = "Example", label = "Example", value = defaults.Example },
	}

	require("translator.ui.fields").open({
		fields = fields,
		on_submit = function(result)
			async.run(submit, result)
		end,
	})
end

return M
