local text = require'src.utils'.text

local str = [[
    --- start
    --- end
]]
print(str)
print('=============')
print(text.trim(str))