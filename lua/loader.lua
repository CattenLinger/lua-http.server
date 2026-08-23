--[[
    Module Loader
--]]
local require, package = require, package;

local loader_computed = {}

---Returns legacy `require` to mimic standard lua api
loader_computed.require = function(self)
    return function(modname)
        local mod, err
        
        mod = self.loaded[modname]
        if mod ~= nil then return mod end;
        
        local mod, err = self.load(modname)
        if not mod then error(err) end
        self.loaded[modname] = mod

        return mod
    end
end

---Return a method to load a module
loader_computed.load = function(self)
    return function(modname)
        local loaders, errs = self.loaders, {}
        -- Scan loader list in reverse order
        for i=#self.loaders, 1, -1 do
            local loader = loaders[i]
            local mod, err = loader(modname)
            if mod then return mod end

            table.insert(errs, err)
        end

        return nil, table.concat(errs, '\t\n')
    end
end

--- Return a default empty loader list
loader_computed.loaders = function() return {} end

--- Return a default empty loaded table
loader_computed.loaded = function() return {} end

local loader_mt = {
    __index = function(self, key)
        local v = loader_computed[key]
        if type(v) == 'function' then v = v(self, key) end
        if v ~= nil then rawset(self, key, v) end
        return v
    end;

    __call     = function(self, ...) return self.require(...) end;
    __newindex = function() --[[ Not allow modifications ]]   end;
}

local M = {}

function M.create(data)
    return setmetatable(data, loader_mt)
end

local M_mt = {
    __index    = M,
    __newindex = function() end,
    __call     = function(self, ...) return self.create(...) end
}

return setmetatable({}, M_mt)