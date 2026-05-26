package.path = './lua/?.lua;'..package.path

local table = require'utils'.table

local str = 'Basic admin:123456'
for item in string.gmatch(str, '[^%s]+') do
    print(item)
end

local tb = table.collect(string.gmatch(str, '[^%s]+'))
for idx, item in ipairs(tb) do
    print(idx, item)
end