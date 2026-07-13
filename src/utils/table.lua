--[[
    Table utility
--]] 

local extable = setmetatable({}, { __index=table })

--[[ Overlay table ]]--
local function overlay_search(backups, _, key)
    local v, idx = nil, #backups
    for idx = #backups, 1, -1 do
        v = backups[idx][key]
        if v ~= nil then return v end
    end
    -- return nil
end

--- Create a table that search value from backups.
--- if use only one param, target will be backups and returns a
--- new table.
--- When a value is missing in the proxied table, searcher will
--- find a not-nil value starts from the end of the backend table
--- list.
---
--- @param target table @set nil to create a new empty table
--- @param backups table @list of tables as it's value backup
--- @return table @target table
--- @return table @the backend table list of this overlay table
function extable.overlay(target, backups)
    if not backups then backups = target; target = {}; end
    local __mt = {}
    __mt.__index = function(...) return overlay_search(backups, ...) end
    return setmetatable(target, __mt), backups
end

--[[ Lazy table ]]
local function lazytable_get(mt, t, k)
    local getter = mt.getters[k]
    if 'function' == type(getter)
    then return getter(t, k);
    else return getter;
    end
end
local function lazytable_cached(mt, t, k)
    local v = lazytable_get(mt, t, k)
    rawset(t, k, v)
    return v
end
function extable.computed(getters, options)
    options = options or {}
    local mt = { getters=getters }
    local ot = options[1] or {}

    if options.cached == true
    then mt.__index = function(...) return lazytable_cached(mt, ...); end
    else mt.__index = function(...) return lazytable_get(mt, ...);    end
    end

    return setmetatable(ot, mt)
end
function extable.lazy(getters)
    return extable.computed(getters, { cached=true })
end

--[[ return keys of a table ]]--
function extable.keys(tb)
    local keys = {}
    for k,_ in pairs(tb) do table.insert(keys, k) end
    return keys
end

--[[
    Copy a table. If target is not gave,
    returns a new table
]]--
function extable.copy(from, to)
    local n = to or {}
    for k, v in pairs(from) do n[k] = v end
    return n
end

--[[ Readonly Table ]]--
local readonly_mt = { __newindex=function()
    error('attempted to modify a readonly table', 2)
end }
--- Make target table readonly
--- @param target table
--- @return table
function extable.readonly(target)
    return setmetatable(target or {}, readonly_mt)
end

---Print a table, 
function extable.print(tb, callback)
    callback = callback or print
    for k, v in pairs(tb) do callback(k, v) end
end

--- Collect items from an iterator
--- if the iterator returns multiple entries,
--- elements will be packed into lists
--- @param iter function iterator function
--- @return table list of elements
function extable.collect(iter)
    local next, list = iter, {}

    local values = table.pack(next())
    local l = #values
    if l == 0 then return list end
    if l == 1 then goto single else goto multiple end

    ::single:: do
        table.insert(list, values[1])
        while values do
            values = next()
            table.insert(list, values)
        end
        return list
    end

    ::multiple:: do
        repeat
            table.insert(list, values)
            values = table.pack(next())
        until not values[1]
        return list
    end
end

--- Make a map from list of entry
---
--- If entry is not a list or only contains
--- 1 element, returns empty table.
--- Otherwise take first two argument and form a table.
---
--- Duplicated keys will be overwrite.
---@param list table @list of {key, value} pairs
---@return table
function extable.from_entries(list)
    local item, result = nil, {}
    local iter, tb, idx = ipairs(list)
    idx, item = iter(tb, idx)
    if not (item and type(item) == 'table' and #item >= 2)
    then return result
    end

    repeat
        local key, value = table.unpack(item)
        result[key] = value
        idx, item = iter(tb, idx)
    until not item
    return result
end

--- Get all entries from table
function extable.entries(t)
    local r = {}
    for key, value in pairs(t) do
        table.insert(r, { key, value })
    end
    return r
end

--- Map index of list as value, and value of list as key
--- @parma list table
--- @return table
function extable.to_set(list)
    local t = {}
    for value, key in ipairs(list) do t[key] = value end
    return t
end

return extable