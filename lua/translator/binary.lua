-- File: lua/translator/binary.lua
-- Locate the compiled Rust backend binary.

local M = {}

function M.get()
	local current = debug.getinfo(1, "S").source:sub(2)
	local root = vim.fn.fnamemodify(current, ":h:h:h")

	local candidates = {
		root .. "/bin/translator",
		root .. "/rust/target/release/translator",
	}

	for _, bin in ipairs(candidates) do
		if vim.fn.executable(bin) == 1 then
			return bin
		end
	end

	vim.notify(
		"translator.nvim: backend binary not found. Run `make build` (requires Rust/cargo).",
		vim.log.levels.ERROR
	)
	return nil
end

return M
