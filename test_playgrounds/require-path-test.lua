#!/usr/bin/env lua

--[[
Try to run this script outside ./snippests will cause an error,
it means, by default, the './' in package.path is related to 
current work directory.
]]--
local ok, testrequire = pcall(require, 'testrequire')
if ok
then print(string.format("SUCCESS: %s, msg: %s", tostring(ok), testrequire.message))
else print(string.format("SUCCESS: %s, msg: %s", tostring(ok), tostring(testrequire)))
end