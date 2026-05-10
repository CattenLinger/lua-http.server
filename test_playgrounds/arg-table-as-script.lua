#!/usr/bin/env lua

--[[
When call from commandline, ARG[0] is the filename.
But if we use loadfile in `> lua`, the arg[0] is the 
lua executable.
]]--
print("ARG0: " .. arg[0])
for i, v in ipairs(arg) do
    print(string.format("%2d : %s", i, v))
end

package.path = package.path .. ';./lib/?.lua;./lib/?/init.lua'

print()
local config_parser = require'config'
local config = config_parser(arg)
for k, v in pairs(config) do
    print(tostring(k)..'\t'..tostring(v))
end
