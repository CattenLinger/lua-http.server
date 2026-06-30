local require, package = require, package
_ENV.require = nil
_ENV.package = nil

--[[
loadfile
loadlib(function)
searchpath(function)

searchers
preload
--]]
local luapath = package.luapath
local luacpath = package.cpath
local searchpath = package.searchpath
local loadlib = package.loadlib
local search = function(name)
    local e = {}
    for _, searcher in ipairs(package.searchers) do
        local path, err = searcher(name)
        if path then return path end
        table.insert(e, err)
    end
    return nil, table.concat(e, '\n\t')
end
print(search('log'))