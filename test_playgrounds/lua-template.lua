#!/usr/bin/env lua
local template = require'template'
local fn = template.compile("<%= title %>\n\n<? if name then ?>Hello, <%= name %> <? else ?> Guest <? end ?>")
template.print(fn, { name = "Catten", title = "Lua Template Test" }, function(s) io.stdout:write(s) end)
print()