std = "lua51"
max_line_length = false
read_globals = { "vim" }
-- 12x: luacheck cannot know vim.g/bo/wo fields
ignore = { "12[23]" }
