--[[
    Meta Table Utils
--]]
local exmeta = {}

local index_hook = {}
exmeta.index_hook = index_hook

--- Create a index hook method.
--- A hook handler value must be a function.
--- A special key '*' is used to register a default handler
--- if no any handler match, can be used as the fallback __index
---
--- @param hooks table a key value table with key handlers
--- @return function, table first is the __index function, second is all the hooks
function index_hook.create(hooks)
    hooks = hooks or {}
    return function(self, key)
        local h = hooks[key] or hooks['*']
        if not h then return rawget(self, h) end
        return h(self, key)
    end, hooks
end

--- Create a default value hook
--- @param value any
--- @return function
function index_hook.default(value)
    if type(value) == 'function' then return value end
    return function() return value end
end
--- Create a lazy value hook
--- @param value function|any provider or a plain value
--- @param raw string|boolean if is 'raw' or true, bypass meta methods
--- @return function
function index_hook.lazy(value, raw)
    if type(value) ~= 'function'
    then value = function() return value end
    end

    if raw == 'raw' or raw == true
    then return function(self, key) rawset(self, key, value()) end
    else return function(self, key) self[key] = value()        end
    end
end
function index_hook.computed(value)
    if type(value) == 'function'
    then return value
    else return function() return value end
    end
end

local newindex_hook = {}
exmeta.newindex_hook = newindex_hook
--- Create a newindex hook method
--- a hook handler value must be a function
---
--- @param hooks table a key value table with key handlers
--- @return function, table first is the __newindex function, second is all the hooks
function newindex_hook.create(hooks)
    hooks = hooks or {}
    return function(self, key, value)
        local h = hooks[key]
        if not h then return rawset(self, key, value) end
        return h(self, key, value)
    end, hooks
end

local newindex_hook_noop = function()  end
--- Returns a method do nothing when set a value
function newindex_hook.ignore()
    return newindex_hook_noop
end

local newindex_hook_reject = function(_, key)
    error('attempted to modify a readonly value: '..key)
end
--- Returns a method throw error when set a value
function newindex_hook.reject()
    return newindex_hook_reject
end

return exmeta