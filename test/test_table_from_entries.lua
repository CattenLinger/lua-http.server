package.path = './lua/?.lua;'..package.path

local table = require'utils'.table

local entries = { {'username', 'admin'}; {'password', 'nopassword'}; }
local tbl = table.from_entries(entries)
table.print(tbl)