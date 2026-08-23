--[[
    Meta Table Utils
--]]
local exmeta = {}

--- Do nothing
function exmeta.noop() end

local void_table_mt_ = {
    __index    = function(self) return self end;
    __newindex = function() end;
}

--- Create a new empty table that always returns
--- it itself when it's field was accessed.
--- 
--- Useful when some thrid-party code try to test a
--- global table
function exmeta.new_void_table()
    return setmetatable({}, void_table_mt_)
end

--[[
    Index Hooks
--]]
local index_hook = {}
exmeta.index_hook = index_hook
exmeta.index = index_hook

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
---
--- Usage:
--- ```lua
--- local defvals = { field=124; method=function(self) print'hello' end; }
--- local tbl = setmetatable({}, { __index=meta.index.default(defvals); })
--- tbl.field -- will be '124'
--- tbl.method() -- print'hello'
--- ```
--- If `opts` is `'raw'` or `{raw=true}` then will use `rawget` to read the `tbl`
---
--- @param tbl table @default value tables
--- @param opts table @options (optional)
--- @return function
function index_hook.default(tbl, opts)
    if opts == 'raw' or (opts or {}).raw then
        return function(self, key) return rawget(tbl, key) end
    end
    
    return function(self, key) return tbl[key] end
end

--- Create a lazy value hook.
--- If value is a function, it will be treated as a value factory.
--- Values will be write to the target table.
---
--- Usage:
--- ```lua
--- local defvals = {}
--- defvals.field=124;
--- defvals.method=function(self, key) function() print'key_name:'..key end; end;
--- local tbl = setmetatable({}, { __index=meta.index.lazy(defvals); })
--- tbl.field -- will be '124'
--- tbl.method() -- 'key_name:method'
--- ```
--- If `opts` is `'raw'` or `{raw=true}` then will use `rawget` to read the `tbl`
---
--- @param getters table @providers
--- @param opts string | table @if is 'raw' is true, use `rawget`
--- @return function
function index_hook.lazy(getters, opts)
    local useraw = (opts == 'raw' or (opts or {}).raw)

    local getval if useraw then getval = rawget else
        getval = function(t, k) return t[k] end
    end

    local setval if useraw then setval = rawset else
        setval = function(t, k, v) t[k] = v end
    end
    
    return function(self, key)
        local g = getval(getters, key)
        if g ~= nil then
            if type(g) == 'function' then g = g(self, key) end
            if g ~= nil then setval(self, key, g) end
        end
        return g
    end
end

---Create a computed value hook.
---Same as `lazy()` but won't write value back to the table
--- @param getters table @providers
--- @param opts string | table @if is 'raw' is true, use `rawget`
--- @return function
function index_hook.computed(getters, opts)
    local useraw = (opts == 'raw' or (opts or {}).raw)
    local getval if useraw then getval = rawget else
        getval = function(t, k) return t[k] end
    end

    return function(self, key)
        local g = getval(getters, key)

        if   g ~= nil and type(g) == 'function'
        then g = g(self, key)
        end

        return g
    end
end

--[[
    New index hooks
--]]
local newindex_hook = {}
exmeta.newindex_hook = newindex_hook
exmeta.newindex = newindex_hook
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

--[[
    Call Hooks
--]]
local call_hooks = {}
exmeta.call_hooks = call_hooks
exmeta.call = call_hooks

--- Create a call hook that call a function on self
---@param name string @function name
function call_hooks.alias(name)
    return function(self, ...)
        return self[name](...)
    end
end

return setmetatable(exmeta, {__newindex=newindex_hook.ignore})