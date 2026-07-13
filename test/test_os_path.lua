os = require'src.utils'.os

local path = os.path('/usr/env/')
print(table.unpack(path))
print(path)
print(path:resolve'/sub')
print(path:parent())
print(path'/sub')