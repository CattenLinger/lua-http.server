--[[
    Module Loader

    This file is aim to be self-contained under standard lua environment.
--]]
local require, package = require, package;
local rawset = function(t, k, v) rawset(t, k, v); return v end;

local type, error    = type, error
local setmetatable   = setmetatable
local insert, concat = table.insert, table.concat

-- The final module reference
local M = {}

--[[
    Prototype and methods
--]]
local getters = {}


local function build_legacy_require(self)
    local loaded, load = self.loaded, self.load

    return function(modname)
        local mod, err

        mod = loaded[modname] if mod ~= nil then return mod end;
        mod, err = load(modname) if not mod then error(err) end

        -- caching the module
        loaded[modname] = mod

        return mod
    end
end

local function build_load_method(self)
    local loaders = self.loaders

    return function(modname)
        local errs = {}

        -- Scan loader list in reverse order
        for i=#loaders, 1, -1 do
            local loader = loaders[i]
            local mod, err = loader(modname)
            -- if module returns no value, mark it as 'true' (means loaded)
            if not err then return mod or true end
            
            insert(errs, err)
        end

        return nil, concat(errs, '\t\n')
    end
end

---Returns legacy `require` to mimic standard lua api
getters.require = function(self, key) return rawset(self, key, build_legacy_require(self)) end

---Return a method to load a module
getters.load = function(self, key) return rawset(self, key, build_load_method(self)) end

--- Return a default empty loader list
getters.loaders = function(self, key) return rawset(self, key, {}) end

--- Return a default empty loaded table
getters.loaded = function(self, key)  return rawset(self, key, {}) end

local loader_mt = {
    __index = function(self, key)
        local v = getters[key] or getters['*']
        if type(v) == 'function' then return v(self, key) end
        return v
    end;

    __call     = function(self, ...) return self.require(...) end;
    __newindex = function() --[[ Not allow modifications ]]   end;
}

--[[
    Module methods
--]]

function M.create(data)
    return setmetatable(data, loader_mt)
end

local M_mt = {
    __index    = M,
    __newindex = function() error('attempted to write to readonly module') end,
    __call     = function(self, ...) return self.create(...) end
}

return setmetatable({}, M_mt)